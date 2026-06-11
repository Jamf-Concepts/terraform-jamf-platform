locals {
  sentinelone_pkg_name   = trimspace(data.local_file.sentinelone_pkg_name.content)
  sentinelone_pkg_source = "${path.module}/support_files/${local.sentinelone_pkg_name}"
}

# Read the versioned filename written by whichever prepare resource ran.
data "local_file" "sentinelone_pkg_name" {
  filename = "${path.module}/support_files/.pkg_name"
  depends_on = [
    terraform_data.prepare_pkg_from_url,
    terraform_data.prepare_pkg_from_path,
  ]
}

# Source: S3 URL — download then extract version.
resource "terraform_data" "prepare_pkg_from_url" {
  count = var.sentinelone_pkg_url != "" && var.sentinelone_pkg_path == "" ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      BUCKET=$(echo '${var.sentinelone_pkg_url}' | sed 's|https://\([^.]*\)\.s3\..*|\1|')
      KEY=$(echo '${var.sentinelone_pkg_url}' | sed 's|https://[^/]*/||')
      TMP='${path.module}/support_files/.download.pkg'
      aws s3 cp "s3://$BUCKET/$KEY" "$TMP"
      PKG_INFO=$(python3 '${path.module}/../../tools/get_pkg_version.py' "$TMP")
      PKG_NAME=$(echo "$PKG_INFO" | sed -n '1p')
      PKG_VERSION=$(echo "$PKG_INFO" | sed -n '2p')
      DEST="$PKG_NAME-$PKG_VERSION.pkg"
      mv "$TMP" '${path.module}/support_files/'"$DEST"
      echo -n "$DEST" > '${path.module}/support_files/.pkg_name'
    EOT
  }

  triggers_replace = [var.sentinelone_pkg_url]
}

# Source: local file path — copy to support_files then extract version.
resource "terraform_data" "prepare_pkg_from_path" {
  count = var.sentinelone_pkg_path != "" ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      PKG_INFO=$(python3 '${path.module}/../../tools/get_pkg_version.py' '${var.sentinelone_pkg_path}')
      PKG_NAME=$(echo "$PKG_INFO" | sed -n '1p')
      PKG_VERSION=$(echo "$PKG_INFO" | sed -n '2p')
      DEST="$PKG_NAME-$PKG_VERSION.pkg"
      cp '${var.sentinelone_pkg_path}' '${path.module}/support_files/'"$DEST"
      echo -n "$DEST" > '${path.module}/support_files/.pkg_name'
    EOT
  }

  triggers_replace = [var.sentinelone_pkg_path]
}

