# outline


structure:

    - global variables that are set in the encrypted sops
    - all of the code, and functions to filter should be open (?)
    - this format will hide my exact emails, and private things, but allows me to track everything clearly in git
    - it might not be ideal.


general idea example:

set globals in sops like so:

```lua
EmailTags = {
    ["a@example.com"] = { "tag1", "tag2" },
    ["b@example.com"] = { "tag2", "tag3" },
    ["c@example.com"] = { "tag1", "tag3" },
    ["d@example.com"] = { "tag1", "tag2", "tag3" },
    ["e@example.com"] = { "tag2" },
    ["f@example.com"] = { "tag1" },
    ["g@example.com"] = { "tag3" },
}
```
and then this can act on incoming emails. and tag them appropriately


