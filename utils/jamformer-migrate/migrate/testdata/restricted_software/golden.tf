resource "jamfplatform_pro_restricted_software" "block_chess" {


  general = {
    name                                 = "Block Chess"
    process_name                         = "Chess.app"
    restrict_exact_process_name          = true
    send_email_notification_on_violation = true
    kill_process                         = true
    delete_application                   = false
    display_message                      = "Chess is not permitted on managed devices."
  }
  scope = {
    targets = {
      all_computers      = false
      computer_ids       = [23, 22]
      computer_group_ids = [13, 12]
    }
    exclusions = {
      computer_ids       = [14, 15]
      computer_group_ids = [13, 12]
    }
  }
}
