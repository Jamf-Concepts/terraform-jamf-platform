resource "jamfpro_restricted_software" "block_chess" {
  name                     = "Block Chess"
  process_name             = "Chess.app"
  match_exact_process_name = true
  send_notification        = true
  kill_process             = true
  delete_executable        = false
  display_message          = "Chess is not permitted on managed devices."

  site_id {
    id = -1
  }

  scope {
    all_computers      = false
    computer_ids       = [23, 22]
    computer_group_ids = [13, 12]

    exclusions {
      computer_ids       = [14, 15]
      computer_group_ids = [13, 12]
    }
  }
}
