locals {
  # Derive the package filename:
  # - From the path (basename) if provided
  # - Otherwise fall back to the explicit filename variable (required for base64/url mode)
  sentinelone_pkg_name = var.sentinelone_pkg_path != "" ? basename(var.sentinelone_pkg_path) : var.sentinelone_pkg_filename

  # Determine the package file source:
  # 1. If a file path is provided, use it directly
  # 2. If an S3 HTTPS URL is provided, download it to a local file
  # 3. If base64 content is provided, decode and write to a local file
  sentinelone_pkg_source = var.sentinelone_pkg_path != "" ? var.sentinelone_pkg_path : (
    var.sentinelone_pkg_url != "" ? "${path.module}/support_files/${var.sentinelone_pkg_filename}" : (
      var.sentinelone_pkg_base64 != "" ? "${path.module}/support_files/${var.sentinelone_pkg_filename}" : ""
    )
  )
}

# Download the .pkg from S3 using the virtual-hosted HTTPS URL.
# Converts https://bucket.s3.region.amazonaws.com/key → s3://bucket/key
# Requires AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the environment.
resource "terraform_data" "download_sentinelone_pkg" {
  count = var.sentinelone_pkg_url != "" && var.sentinelone_pkg_path == "" ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      BUCKET=$(echo '${var.sentinelone_pkg_url}' | sed 's|https://\([^.]*\)\.s3\..*|\1|')
      KEY=$(echo '${var.sentinelone_pkg_url}' | sed 's|https://[^/]*/||')
      aws s3 cp "s3://$BUCKET/$KEY" '${path.module}/support_files/${var.sentinelone_pkg_filename}'
    EOT
  }

  triggers_replace = [var.sentinelone_pkg_url]
}

resource "local_file" "sentinelone_pkg" {
  count          = var.sentinelone_pkg_base64 != "" && var.sentinelone_pkg_path == "" && var.sentinelone_pkg_url == "" ? 1 : 0
  content_base64 = var.sentinelone_pkg_base64
  filename       = "${path.module}/support_files/${var.sentinelone_pkg_filename}"
}
