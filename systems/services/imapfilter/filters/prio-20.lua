-- Priority: 2
-- Function to move emails from a specific sender to the Filtered folder
function filter_sender()
    -- Select all messages from the inbox
    messages = account.INBOX:select_all()

    -- Filter messages from a specific sender
    results = messages:contain_from('amazon+rueckgabe=amazon.de@knoc.one')

    -- Move matching messages to the Filtered folder
    results:move_messages(account.Processed)

    print(string.format("Moved %d messages to Processed folder", #results))
end

-- Run the filter once
filter_sender()

