resource "jamfplatform_pro_script" "hello_world" {
  name            = "Hello World"
  script_contents = file("${path.root}/support_files/scripts/hello_world.sh")
  category_id     = jamfplatform_pro_category.engineering.id
  priority        = "AFTER"
}
