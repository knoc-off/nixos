-- Define an array of subjects to match
subjects_to_match = {
    "Newsletter",
    "Promotional offer",
    "Weekly update",
    "Reminder"
}

-- Function to check if a string matches any of the subjects in the array
function matches_subject(subject)
    for _, match_subject in ipairs(subjects_to_match) do
        if string.find(subject:lower(), match_subject:lower()) then
            return true
        end
    end
    return false
end

-- Function to tag new messages
function tag_new_messages()
    -- Select all new (unseen) messages from the inbox
    new_messages = account.INBOX:is_unseen()

    -- Filter messages that match the subject
    to_be_tagged = new_messages:match_field("SUBJECT", matches_subject)

    -- Tag matching messages with a custom flag
    to_be_tagged:add_flags("$RemoveIn3Days")

    print(string.format("Tagged %d new messages for removal in 3 days", #to_be_tagged))
end

-- Function to remove old tagged messages
function remove_old_tagged_messages()
    -- Select messages that are tagged and older than 3 days
    to_remove = account.INBOX:has_flag("$RemoveIn3Days") * account.INBOX:is_older(3)

    -- Move these messages to trash
    to_remove:move_messages(account.Trash)

    print(string.format("Moved %d messages to trash", #to_remove))
end

-- Main function to run both operations
function process_messages()
    tag_new_messages()
    remove_old_tagged_messages()
end

-- Run the process once
process_messages()

-- To run this process periodically, uncomment the following line:
-- become_daemon(3600, process_messages)  -- Run every hour
