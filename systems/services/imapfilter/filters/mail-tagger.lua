-- Priority: 3
-- Function to tag emails based on the sender's email address.

function filter()
    messages = account.INBOX:select_all()
    for email, tags in pairs(emailsFrom) do
        local from_matches = messages:contain_from(email)
        if from_matches then
            from_matches:add_flags(tags)
        end
    end
    for email, tags in pairs(emailsTo) do
        local to_matches = messages:contain_to(email)
        if to_matches then
            to_matches:add_flags(tags)
        end
    end


    for _, mesg in ipairs(messages) do
        mbox, uid = table.unpack(mesg)
        flags = mbox[uid]:fetch_flags()

        -- recursively print the Flags
        function print_flags(flags)
            for k, v in pairs(flags) do
                if type(v) == "table" then
                    print(k)
                    print_flags(v)
                else
                    print(k, v)
                end
            end
        end

        print_flags(flags)

        print("\n-----------------------------------------------\n")
    end




end

-- become_daemon(60 * 2, filter) -- every 2 minutes
filter()





