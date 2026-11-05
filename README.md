# multi-agent
AI plugins for herdr based multi agent workflows. 

This repo is a Claude Code plugin marketplace (`multi-agent`) containing:

- `herdr-multi-agent` — skills for coordinating multiple coding agents in herdr panes (`plugins/herdr-multi-agent/`).

## Related

- [herdr](https://github.com/herdrdev/herdr) — the terminal multiplexer for coding agents these plugins control.
- [herdr skill](https://github.com/herdrdev/herdr/tree/master/skills/herdr) — the upstream skill for driving herdr from Claude Code, published in the herdr repo.

## Install

```
/plugin marketplace add kerryhatcher/multi-agent
/plugin install herdr-multi-agent@multi-agent
```

To work on the marketplace locally, add the checkout path instead of the GitHub slug.

