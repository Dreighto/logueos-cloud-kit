# logueos-cloud-kit

The operating manual and the room-independent skills that dreighto's agents
use, for Claude Code cloud sessions. Generated from the private logueos-fleet
repo by `fleet/cloud-kit-publish.sh`; edits made here are overwritten.

Cloud environment setup script (claude.ai/code, environment settings):

```bash
#!/bin/bash
git clone --depth 1 https://github.com/Dreighto/logueos-cloud-kit.git /tmp/cloud-kit && bash /tmp/cloud-kit/fleet/cloud-setup.sh || echo "cloud kit setup failed; the session starts without it"
```
