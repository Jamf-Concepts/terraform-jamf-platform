#!/usr/bin/env python3
"""
Migrate Terraform module resource types from deploymenttheory/jamfpro to
Jamf-Concepts/jamfplatform.

Usage:
    python3 utils/migrate_provider_resources.py [modules_dir]

    modules_dir defaults to ./modules relative to the script's parent directory.

Transforms applied:
    jamfplatform_pro_smart_computer_group       → jamfplatform_device_group (computer)
    jamfplatform_pro_smart_mobile_device_group  → jamfplatform_device_group (mobile)
    jamfplatform_pro_macos_configuration_profile_plist
        → jamfplatform_pro_macos_configuration_profile
    jamfplatform_pro_mobile_device_configuration_profile_plist
        → jamfplatform_pro_mobile_device_configuration_profile
    jamfplatform_pro_api_integration            → jamfplatform_pro_api_client
    jamfplatform_pro_client_checkin             → jamfplatform_pro_computer_check_in_settings

Schema changes:
    - Smart groups: criteria blocks converted from HCL block syntax
      (name/search_type/and_or/priority attrs) to list-of-objects syntax
      (criteria/operator attrs). group_type and device_type inserted.
    - Group references: .id → .jamf_pro_id (computed classic-API numeric ID).
    - Config profiles: flat top-level attrs wrapped in general = {}, scope
      restructured to scope = { targets = {} }, payload_validate dropped,
      deployment_method renamed to distribution_method (mobile only).
    - api_client: authorization_scopes → api_roles, credential_rotation = "1"
      added to enable secret generation.
    - computer_check_in_settings: create_hooks → create_login_hook,
      hook_log → login_hook_log, hook_policies → login_hook_policies,
      enable_local_configuration_profiles removed (no longer exists).
"""

import os
import re
import sys


# ── helpers ──────────────────────────────────────────────────────────────────

def find_block_end(text, brace_open):
    """Return index after the matching closing '}' for brace_open."""
    depth = 0
    i = brace_open
    while i < len(text):
        c = text[i]
        if c == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                if text[i] == '\\':
                    i += 1
                i += 1
        elif c == '#':
            while i < len(text) and text[i] != '\n':
                i += 1
            continue
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def get_indent(text, match_start):
    """Return leading whitespace on the line where match_start sits."""
    line_start = text.rfind('\n', 0, match_start) + 1
    m = re.match(r'^(\s*)', text[line_start:])
    return m.group(1) if m else ''


# ── smart group transformation ────────────────────────────────────────────────

def parse_criteria_hcl(body):
    """
    Parse all 'criteria { ... }' blocks from HCL body text.
    Returns list of dicts with raw attribute values.
    """
    results = []
    pos = 0
    while True:
        m = re.search(r'\bcriteria\s*\{', body[pos:])
        if not m:
            break
        brace_start = pos + m.start() + m.group(0).index('{')
        brace_end = find_block_end(body, brace_start)
        inner = body[brace_start + 1:brace_end - 1]
        attrs = {}
        for am in re.finditer(r'^\s*(\w+)\s*=\s*(.+?)\s*$', inner, re.MULTILINE):
            attrs[am.group(1)] = am.group(2).strip()
        results.append(attrs)
        pos = brace_end
    return results


def format_criteria_list(criteria_list, ind):
    """Format criteria as new list-of-objects HCL."""
    out = [f'{ind}criteria = [']
    for idx, c in enumerate(criteria_list):
        out.append(f'{ind}  {{')
        if idx > 0 and 'and_or' in c:
            out.append(f'{ind}    and_or   = {c["and_or"]}')
        out.append(f'{ind}    criteria = {c.get("name", "")}')
        out.append(f'{ind}    operator = {c.get("search_type", "")}')
        out.append(f'{ind}    value    = {c.get("value", "")}')
        out.append(f'{ind}  }},')
    out.append(f'{ind}]')
    return '\n'.join(out)


def remove_criteria_blocks(body):
    """Strip all 'criteria { ... }' blocks from body text."""
    result = []
    pos = 0
    while True:
        m = re.search(r'\n\s*criteria\s*\{', body[pos:])
        if not m:
            break
        abs_start = pos + m.start()
        brace_pos = pos + m.start() + m.group(0).index('{')
        brace_end = find_block_end(body, brace_pos)
        result.append(body[pos:abs_start])
        pos = brace_end
    result.append(body[pos:])
    return ''.join(result)


def transform_smart_groups(content, old_type, device_type):
    """Transform old smart group resources to jamfplatform_device_group."""
    result = []
    pos = 0
    pat = re.compile(r'resource\s+"' + re.escape(old_type) + r'"\s+"([^"]+)"\s*\{')

    while True:
        m = pat.search(content, pos)
        if not m:
            break
        indent = get_indent(content, m.start())
        brace_pos = m.start() + m.group(0).rindex('{')
        block_end = find_block_end(content, brace_pos)
        body = content[brace_pos + 1:block_end - 1]
        label = m.group(1)

        criteria = parse_criteria_hcl(body)
        body_no_criteria = remove_criteria_blocks(body)
        body_indent = indent + '  '

        lines = [f'{indent}resource "jamfplatform_device_group" "{label}" {{']
        found_name = False
        for line in body_no_criteria.split('\n'):
            stripped = line.strip()
            if not stripped:
                continue
            lines.append(line)
            if re.match(r'\s*name\s*=', line) and not found_name:
                found_name = True
                lines.append(f'{body_indent}group_type  = "smart"')
                lines.append(f'{body_indent}device_type = "{device_type}"')

        if criteria:
            lines.append('')
            lines.append(format_criteria_list(criteria, body_indent))
        lines.append(f'{indent}}}')

        result.append(content[pos:m.start()])
        result.append('\n'.join(lines))
        pos = block_end

    result.append(content[pos:])
    return ''.join(result)


# ── config profile transformation ─────────────────────────────────────────────

MACOS_GENERAL_ATTRS = {
    'name', 'description', 'level', 'distribution_method',
    'redeploy_on_update', 'category_id', 'user_removable', 'payloads',
}
MOBILE_GENERAL_ATTRS = {
    'name', 'description', 'level', 'distribution_method', 'deployment_method',
    'redeploy_on_update', 'redeploy_days_before_certificate_expires',
    'category_id', 'payloads',
}

SCOPE_TARGET_COMPUTER = {
    'all_computers', 'computer_group_ids', 'computer_ids',
    'building_ids', 'department_ids',
}
SCOPE_TARGET_MOBILE = {
    'all_mobile_devices', 'mobile_device_group_ids', 'mobile_device_ids',
}


def parse_scope_inner(inner_text, is_mobile):
    target_keys = SCOPE_TARGET_MOBILE if is_mobile else SCOPE_TARGET_COMPUTER
    targets = {}
    for line in inner_text.split('\n'):
        m = re.match(r'\s*(\w+)\s*=\s*(.+)', line)
        if m:
            k, v = m.group(1).strip(), m.group(2).strip()
            if k in target_keys:
                targets[k] = v
    return targets


def parse_profile_body(body, is_mobile):
    general_attr_names = MOBILE_GENERAL_ATTRS if is_mobile else MACOS_GENERAL_ATTRS
    for_each_lines = []
    general_lines = []
    scope_targets = {}
    post_blocks = []

    lines = body.split('\n')
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped or stripped.startswith('#'):
            i += 1
            continue

        if re.match(r'\s*for_each\s*=', line):
            for_each_lines.append(line)
            i += 1
            continue

        if re.match(r'\s*depends_on\s*=', line):
            block = [line]
            if '[' in line:
                while ']' not in line:
                    i += 1
                    line = lines[i]
                    block.append(line)
            post_blocks.append(('depends_on', block))
            i += 1
            continue

        if re.match(r'\s*lifecycle\s*\{', stripped):
            depth = line.count('{') - line.count('}')
            block = [line]
            i += 1
            while i < len(lines) and depth > 0:
                depth += lines[i].count('{') - lines[i].count('}')
                block.append(lines[i])
                i += 1
            post_blocks.append(('lifecycle', block))
            continue

        if re.match(r'\s*scope\s*\{', stripped):
            scope_lines = []
            depth = line.count('{') - line.count('}')
            i += 1
            while i < len(lines) and depth > 0:
                depth += lines[i].count('{') - lines[i].count('}')
                if depth > 0:
                    scope_lines.append(lines[i])
                i += 1
            scope_targets = parse_scope_inner('\n'.join(scope_lines), is_mobile)
            continue

        if re.match(r'\s*payload_validate\s*=', line):
            i += 1
            continue

        m = re.match(r'\s*(\w+)\s*=', line)
        if m:
            attr = m.group(1)
            if attr == 'deployment_method' and is_mobile:
                line = line.replace('deployment_method', 'distribution_method', 1)
                attr = 'distribution_method'
            if attr in general_attr_names:
                general_lines.append(line)
            i += 1
            continue

        i += 1

    return for_each_lines, general_lines, scope_targets, post_blocks


def transform_config_profiles(content, old_type, new_type, is_mobile):
    result = []
    pos = 0
    pat = re.compile(r'resource\s+"' + re.escape(old_type) + r'"\s+"([^"]+)"\s*\{')

    while True:
        m = pat.search(content, pos)
        if not m:
            break
        indent = get_indent(content, m.start())
        brace_pos = m.start() + m.group(0).rindex('{')
        block_end = find_block_end(content, brace_pos)
        body = content[brace_pos + 1:block_end - 1]
        label = m.group(1)
        body_indent = indent + '  '

        for_each, general_lines, scope_targets, post_blocks = parse_profile_body(body, is_mobile)

        lines = [f'{indent}resource "{new_type}" "{label}" {{']

        if for_each:
            for l in for_each:
                lines.append(l)
            lines.append('')

        lines.append(f'{body_indent}general = {{')
        for gl in general_lines:
            lines.append(f'{body_indent}  {gl.lstrip()}')
        lines.append(f'{body_indent}}}')

        if scope_targets:
            lines.append('')
            lines.append(f'{body_indent}scope = {{')
            lines.append(f'{body_indent}  targets = {{')
            for k, v in scope_targets.items():
                lines.append(f'{body_indent}    {k} = {v}')
            lines.append(f'{body_indent}  }}')
            lines.append(f'{body_indent}}}')

        for kind, blk in post_blocks:
            lines.append('')
            for l in blk:
                lines.append(l)

        lines.append(f'{indent}}}')

        result.append(content[pos:m.start()])
        result.append('\n'.join(lines))
        pos = block_end

    result.append(content[pos:])
    return ''.join(result)


# ── api_integration → api_client ──────────────────────────────────────────────

def transform_api_integration(content):
    content = content.replace(
        'resource "jamfplatform_pro_api_integration"',
        'resource "jamfplatform_pro_api_client"')
    content = content.replace(
        'data "jamfplatform_pro_api_integration"',
        'data "jamfplatform_pro_api_client"')
    content = re.sub(r'\bjamfplatform_pro_api_integration\.', 'jamfplatform_pro_api_client.', content)
    content = re.sub(r'\bauthorization_scopes\b', 'api_roles', content)

    def add_cred_rotation(m):
        text = m.group(0)
        if 'credential_rotation' in text:
            return text
        return re.sub(
            r'(\s*enabled\s*=\s*\S+)',
            lambda x: x.group(0) + '\n' + re.match(r'(\s*)', x.group(0)).group(1) + 'credential_rotation = "1"',
            text, count=1)

    content = re.sub(
        r'resource "jamfplatform_pro_api_client" "[^"]+"\s*\{[^}]*enabled\s*=\s*\S+[^}]*\}',
        add_cred_rotation,
        content, flags=re.DOTALL)

    return content


# ── client_checkin → computer_check_in_settings ───────────────────────────────

def transform_checkin(content):
    content = content.replace(
        'resource "jamfplatform_pro_client_checkin"',
        'resource "jamfplatform_pro_computer_check_in_settings"')
    content = re.sub(r'\bjamfplatform_pro_client_checkin\.', 'jamfplatform_pro_computer_check_in_settings.', content)
    content = re.sub(r'\bcreate_hooks\b', 'create_login_hook', content)
    content = re.sub(r'\bhook_log\b', 'login_hook_log', content)
    content = re.sub(r'\bhook_policies\b', 'login_hook_policies', content)
    content = re.sub(r'\n\s*enable_local_configuration_profiles\s*=\s*\S+', '', content)
    return content


# ── reference renames ─────────────────────────────────────────────────────────

def rename_references(content):
    content = re.sub(
        r'\bjamfplatform_pro_macos_configuration_profile_plist\.',
        'jamfplatform_pro_macos_configuration_profile.',
        content)
    content = re.sub(
        r'\bjamfplatform_pro_mobile_device_configuration_profile_plist\.',
        'jamfplatform_pro_mobile_device_configuration_profile.',
        content)
    # Smart group references: rename type prefix and convert .id → .jamf_pro_id
    content = re.sub(
        r'\bjamfplatform_pro_smart_computer_group\.([a-zA-Z0-9_-]+)\.id\b',
        r'jamfplatform_device_group.\1.jamf_pro_id',
        content)
    content = re.sub(
        r'\bjamfplatform_pro_smart_mobile_device_group\.([a-zA-Z0-9_-]+)\.id\b',
        r'jamfplatform_device_group.\1.jamf_pro_id',
        content)
    content = re.sub(
        r'\bjamfplatform_pro_smart_computer_group\.',
        'jamfplatform_device_group.',
        content)
    content = re.sub(
        r'\bjamfplatform_pro_smart_mobile_device_group\.',
        'jamfplatform_device_group.',
        content)
    # Catch any .id refs on device_group that slipped through
    content = re.sub(
        r'\bjamfplatform_device_group\.([a-zA-Z0-9_-]+)\.id\b',
        r'jamfplatform_device_group.\1.jamf_pro_id',
        content)
    return content


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)

    if len(sys.argv) > 1:
        modules_dir = sys.argv[1]
    else:
        modules_dir = os.path.join(repo_root, 'modules')

    if not os.path.isdir(modules_dir):
        print(f"Error: modules directory not found: {modules_dir}", file=sys.stderr)
        sys.exit(1)

    tf_files = []
    for root, dirs, files in os.walk(modules_dir):
        for fn in files:
            if fn.endswith('.tf'):
                tf_files.append(os.path.join(root, fn))

    changed = 0
    for path in sorted(tf_files):
        with open(path) as f:
            content = f.read()
        original = content

        content = rename_references(content)
        content = transform_smart_groups(content, 'jamfplatform_pro_smart_computer_group', 'computer')
        content = transform_smart_groups(content, 'jamfplatform_pro_smart_mobile_device_group', 'mobile')
        content = transform_config_profiles(content,
            'jamfplatform_pro_macos_configuration_profile_plist',
            'jamfplatform_pro_macos_configuration_profile', is_mobile=False)
        content = transform_config_profiles(content,
            'jamfplatform_pro_mobile_device_configuration_profile_plist',
            'jamfplatform_pro_mobile_device_configuration_profile', is_mobile=True)
        content = transform_api_integration(content)
        content = transform_checkin(content)

        if content != original:
            with open(path, 'w') as f:
                f.write(content)
            print(f"  Modified: {os.path.relpath(path, repo_root)}")
            changed += 1

    print(f"\nTotal files modified: {changed}")


if __name__ == '__main__':
    main()
