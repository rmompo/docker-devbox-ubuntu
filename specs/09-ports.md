# 09 - Published ports

## Context
A server that runs inside a container (an Angular dev server, a local web server, a Spring Boot API with its Swagger console) can only be opened from Windows if its port is published. Docker decides the published ports when the container is created (`docker create -p ...`) and cannot add one to an existing container.

## Reasoning
1. The ports are a creation-time choice -> `dkdb-container-create` asks for them (and accepts `-Ports`), like the volumes.
2. The container has a weak password by design (spec 04) -> the default host ip is `127.0.0.1`, so only this computer reaches the ports; another ip (`0.0.0.0` for the whole network) is possible but warns.
3. `docker create -p` fails late (when the container starts) if the host port is taken -> the script checks the host ports before creating anything and says who is using them.
4. Windows reserves port ranges (Hyper-V, WSL, Docker Desktop) that Docker cannot publish -> the script reads them with `netsh` and refuses a port inside one.
5. Ports cannot be changed afterwards -> nothing in the scripts pretends to: the message says to create a new container. With Mutagen (spec 08) the projects come back from the host folder, so recreating is cheap.
6. A container cannot see its own published ports -> the host writes them into the state file (`~/.devbox-state`) so that `dkdb-info.sh` can show them.
7. No port is published by default (an empty answer), so nothing changes for anybody who does not ask for them.

## Decision
- **Format of a mapping:** `[ip:]host_port:container_port[/tcp|/udp]`. A single number `N` means `N:N`. Several mappings are separated by commas (semicolons and spaces also work). The protocol is `tcp` unless `/udp` is given. IPv4 only. Port ranges are not supported.
- **Ask or pass:** `dkdb-container-create` asks `Ports [none]` after the volume type, with a text that explains the format, the default ip and the creation-time limit. `-Ports <list>` skips the question; `-Ports ""` publishes nothing.
- **Checks before creating anything** (any error stops the script and creates nothing): the format; no repeated `ip:host_port/protocol`; the host port is not in use (`Get-NetTCPConnection` for TCP, `Get-NetUDPEndpoint` for UDP; the message names the process and its PID); the host port is not inside a Windows excluded range (`netsh interface ipv4 show excludedportrange protocol=<tcp|udp>`). Both checks are best effort: when they cannot be read the port is accepted and Docker has the last word when the container starts.
- **Warning, not error:** a host ip other than `127.0.0.1`.
- **Docker call:** one `-p <ip>:<host_port>:<container_port>/<protocol>` per mapping, always with the explicit ip and protocol.
- **Reading them back:** `Get-DevboxContainerPorts` reads `HostConfig.PortBindings` with `docker inspect`. `dkdb-info` (host) prints `port <ip>:<host_port> -> <container_port>/<protocol>` under each container, or `ports: none published`.
- **State file:** `Update-DevboxContainerState` writes `ports=<count>` and one `port|<ip>|<host_port>|<container_port>/<protocol>` line per port. `ports=` missing means that an older host script wrote the file; `ports=0` means none. `dkdb-info.sh` prints them under `Ports`, in the same layout as the host.
- **Versions:** the image does not change (no `Dockerfile` or `entrypoint.sh` change); only the scripts do.

## Consequences
- Existing containers keep working and show `none published`; to get ports, create a new container.
- The host port is the one that matters for URLs: `-Ports 3100:3000` makes a dev server that listens on 3000 inside reachable at `http://localhost:3100`. A tool that has the host port hard coded (for example a local server that expects `http://localhost:8080`) needs the same number on both sides.
- A server inside the container must listen on all its interfaces (`0.0.0.0`), not only on `127.0.0.1`, or the published port will not reach it.
- Other network options of `docker create` (`--dns`, MTU, a proxy, `--add-host`) are not part of this spec. They are evaluated after trying a container with ports on the real network (VPN); if they are needed they get their own section here.
