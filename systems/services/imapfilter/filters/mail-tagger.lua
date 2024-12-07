-- Priority: 3
-- Function to tag emails based on the sender's email address.

-- table:
-- EmailTags = {
--     ["a@example.com"] = { "tag1", "tag2" },
--     ["b@example.com"] = { "tag2", "tag3" },
--     ["c@example.com"] = { "tag1", "tag3" },
--     ["d@example.com"] = { "tag1", "tag2", "tag3" },
--     ["e@example.com"] = { "tag2" },
--     ["f@example.com"] = { "tag1" },
--     ["g@example.com"] = { "tag3" },
-- }
-- Assume EmailTags is defined in the global scope.
--

function filter()
    messages = account.INBOX:select_all()
    for email, tags in pairs(EmailTags) do
        local from_matches = messages:contain_from(email)
        local to_matches = messages:contain_to(email)

        if from_matches then
            from_matches:add_flags(tags)
        end
        if to_matches then
            to_matches:add_flags(tags)
        end
    end
end

