# SURVIVE Runbook: Port 8000 Is Already In Use

**Phase 0 - SURVIVE scenario 3 of 3**

## The situation

You try to start your app in Docker on port 8000, and Docker refuses with an error like "port is already allocated." Something else is already listening on 8000. This happens constantly in real work - a leftover container, another app, or a forgotten process holds the port.

This runbook teaches you to find what is using a port, free it, and start your own container in its place. These are core troubleshooting skills you will use forever.

Every command block tells you **which server** and **which user** you are. You do all of this on your **lab server** as **ec2-user**.

> **Note on sudo:** if the BUILD module's `usermod -aG docker ec2-user` has taken effect (you logged out and back in), you can run `docker` without `sudo`. If not, prefix every `docker` command with `sudo`.

---

## Step 1: Reproduce the problem

On your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/phase00-orientation/survive/docker-port-conflict/inject.sh
```

(Adjust the path if your scenario copy lives elsewhere.)

This starts a container that grabs port 8000.

---

## Step 2: Try to start your app and see it fail

Attempt to run your own container on port 8000.

On your **lab server**, as **ec2-user**:

```bash
docker run -d --name my-app -p 8000:8000 python:3.12-slim python -m http.server 8000
```

`docker run` starts a container. `-d` runs it in the background. `--name my-app` names it. `-p 8000:8000` maps host port 8000 to container port 8000.

Expected output (this is the symptom):

```
docker: Error response from daemon: driver failed programming external connectivity on endpoint my-app: Bind for 0.0.0.0:8000 failed: port is already allocated
```

The port is taken. Time to find out by what.

---

## Step 3: See what is listening on port 8000

Use `ss` to list listening sockets.

Still on your **lab server**, as **ec2-user**:

```bash
sudo ss -tlnp | grep :8000
```

Breaking this down:
- `ss` shows socket statistics.
- `-t` = TCP, `-l` = listening only, `-n` = show numeric ports (not names), `-p` = show the owning process.
- `sudo` is needed to see the process for ports owned by other users.
- `grep :8000` filters to just port 8000.

Expected output (yours will differ):

```
LISTEN 0  4096  0.0.0.0:8000  0.0.0.0:*  users:(("docker-proxy",pid=12345,fd=4))
```

`docker-proxy` tells you a **Docker container** is holding the port, not a plain process.

---

## Step 4: Find which container it is

List running containers and their port mappings.

Still on your **lab server**, as **ec2-user**:

```bash
docker ps
```

`docker ps` lists running containers.

Expected output (yours will differ, truncated):

```
CONTAINER ID   IMAGE               ...   PORTS                    NAMES
a1b2c3d4e5f6   python:3.12-slim    ...   0.0.0.0:8000->8000/tcp   port-hog
```

The container `port-hog` maps `0.0.0.0:8000->8000/tcp`. That is the culprit.

---

## Step 5: Stop and remove the offending container

Free the port by removing the container.

Still on your **lab server**, as **ec2-user**:

```bash
docker rm -f port-hog
```

`docker rm` removes a container. `-f` forces it (stops it first if running). `port-hog` is the name from the previous step.

Expected output (yours will differ):

```
port-hog
```

Confirm the port is now free:

```bash
sudo ss -tlnp | grep :8000
```

Expected output (empty - nothing printed means nothing is listening on 8000):

```

```

---

## Step 6: Remove your failed container attempt

Your earlier `docker run` created a stopped `my-app` container that could not bind the port. Remove it so you can reuse the name.

Still on your **lab server**, as **ec2-user**:

```bash
docker rm -f my-app
```

If it prints an error that no such container exists, that is fine - it means there was nothing to remove.

---

## Step 7: Start your app on the now-free port

Run your container again. This time the port is free.

Still on your **lab server**, as **ec2-user**:

```bash
docker run -d --name my-app -p 8000:8000 python:3.12-slim python -m http.server 8000
```

Expected output (yours will differ - a long container ID):

```
7f8e9d0c1b2a3f4e5d6c7b8a9f0e1d2c3b4a5f6e7d8c9b0a1f2e3d4c5b6a7f8e
```

A container ID (not an error) means it started.

---

## Step 8: Confirm your app is running and serving

Check the container is up:

Still on your **lab server**, as **ec2-user**:

```bash
docker ps --filter name=my-app
```

`--filter name=my-app` shows only your container.

Expected output (yours will differ, truncated):

```
CONTAINER ID   IMAGE              ...   PORTS                    NAMES
7f8e9d0c1b2a   python:3.12-slim   ...   0.0.0.0:8000->8000/tcp   my-app
```

Now confirm it actually responds on the port:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000
```

`curl` makes an HTTP request. `-s` is silent, `-o /dev/null` discards the body, `-w "%{http_code}\n"` prints just the status code.

Expected output (yours will differ):

```
200
```

`200` means the server answered successfully.

---

## Step 9: Validate

Run the validator.

Still on your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/phase00-orientation/survive/docker-port-conflict/validate.sh
```

Expected output when fixed:

```
[validate] PASS: 'my-app' is running and serving on port 8000
```

If it fails, read the message and repeat the step it names.

---

## What you learned

- `ss -tlnp` shows what is listening on a port and which process owns it.
- `docker-proxy` in that output means a container holds the port; `docker ps` names it.
- Free a port held by a container with `docker rm -f <name>`.
- Always confirm both that the container is running (`docker ps`) and that it actually responds (`curl`).
