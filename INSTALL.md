# Install Docker and start the course Hadoop cluster

From Recitation 3 on, and for Homework 1, you run a small Hadoop cluster on your own laptop: six Docker
containers (NameNode, two DataNodes, ResourceManager, NodeManager, JobHistory server). This page gets you
from nothing to a WordCount job running on that cluster.

**Do sections 1-5 at home, on a good connection.** They download about 1.5 GB: Docker Desktop is
570-630 MB, the Hadoop image build about 600 MB (the Hadoop 3.4.1 release is 494 MB, the Java base image
about 90 MB, plus Ubuntu packages), the Maven image and the Java dependencies about 260 MB. A full classroom can't download that over one Wi-Fi network. In class we
only check that everything works.

Plan 30-60 minutes; most of it is waiting for downloads. You need:

- a 64-bit laptop with **8 GB of RAM or more** (Docker's own minimum for Windows is 8 GB);
- **10 GB of free disk** (images 1.6 GB, Docker Desktop and, on Windows, Ubuntu on top);
- admin rights on the laptop (installing Docker or WSL asks for them);
- a GitHub account (section 4).

Commands go in a terminal: **Terminal** on macOS, the **Ubuntu** app on Windows (section 2B), any terminal
on Linux. Lines starting with `$` are what you type, without the `$`; the rest is what you should see.

| Your laptop | Do |
|---|---|
| Mac (Apple Silicon M1-M5, or Intel) | 2A |
| Windows 10 or 11 | 2B |
| Ubuntu or Debian Linux | 2C |

Then everyone does 3, 4 and 5.

## 1. Free disk space and memory

Check you have 10 GB free (macOS: Apple menu > System Settings > General > Storage; Windows: File Explorer >
This PC; Linux: `df -h ~`). Close what you don't need: the cluster itself uses about 2 GB of memory while a
job runs (we measured a 2.0 GB peak for the WordCount job in section 5).

## 2A. macOS

Docker Desktop supports "the current and two previous major macOS releases" and needs "at least 4 GB of
RAM" (docs.docker.com/desktop/setup/install/mac-install). Check your macOS version under Apple menu > About
This Mac and update first if it is older than that.

1. **Which chip do you have?**

   ```
   $ uname -m
   arm64
   ```

   `arm64` = Apple Silicon, `x86_64` = Intel. You will pick the matching Docker download.

2. **git, make and python3** come with Apple's Command Line Tools:

   ```
   $ xcode-select --install
   ```

   A window asks to install the tools: click **Install** (a few minutes). If it says the tools are already
   installed, that's fine. Check:

   ```
   $ git --version && make --version | head -1 && python3 --version
   git version 2.54.0 (Apple Git-157)
   GNU Make 3.81
   Python 3.9.6
   ```

   Your version numbers may differ; Python must be 3.9 or newer.

3. **Docker Desktop.** Download it from https://docs.docker.com/desktop/setup/install/mac-install/ with the
   button for your chip ("Apple silicon" or "Intel chip"). Open `Docker.dmg`, drag Docker to
   **Applications**, then start Docker from Applications. Accept the Docker Subscription Service Agreement
   (free for education and personal use). Docker Desktop starts; a whale appears in the menu bar.

   Recent Docker Desktop installs its command-line tools in `~/.docker/bin` and adds that to your `PATH`:
   **open a new Terminal window** before typing `docker`.

4. **Memory.** Docker Desktop's memory limit "defaults to 50% of your host's memory"
   (docs.docker.com/desktop/settings-and-maintenance/settings). Open Docker Desktop > **Settings** (gear) >
   **Resources** and set **Memory limit** to **6 GB** if your Mac has 12 GB or more. On an 8 GB Mac leave
   the default 4 GB and close other apps while jobs run (the WordCount job below peaked at 2.0 GB). Click
   **Apply**.

Apple Silicon needs nothing else: our Hadoop image is built natively for arm64, nothing runs emulated.
Continue with section 3.

## 2B. Windows 10/11: WSL2 + Docker Desktop

Everything for the course runs **inside Linux (Ubuntu) on Windows**, through WSL2. You never run course
commands in PowerShell, except the installation steps below.

Requirements from Microsoft and Docker (checked on 2026-11-01):

- WSL: "Windows 10 version 2004 and higher (Build 19041 and higher) or Windows 11"
  (learn.microsoft.com/windows/wsl/install).
- Docker Desktop: "Windows 10 64-bit: ... version 22H2 (build 19045)", "Windows 11 64-bit: ... version 23H2
  (build 22631) or higher", "WSL version 2.1.5 or later", "8GB system RAM", and "Enable hardware
  virtualization in BIOS/UEFI" (docs.docker.com/desktop/setup/install/windows-install). Windows Home is
  fine: "Windows Home or Education editions only allow you to run Linux containers", and Linux containers
  are all we use.

Check your build: press Win+R, type `winver`, Enter. Update Windows first if it is older.

1. **Install WSL and Ubuntu.** Right-click the Start button > **Terminal (Admin)** or **Windows PowerShell
   (Admin)**, then:

   ```
   PS> wsl --install
   ```

   This "will enable the features necessary to run WSL and install the Ubuntu distribution of Linux".
   **Restart Windows** when it is done.

   - If `wsl --install` only prints help text, WSL is already there: run `wsl --install -d Ubuntu`.
   - If it hangs at 0.0%: `wsl --install --web-download -d Ubuntu`.

2. **Create your Linux user.** After the restart, Ubuntu opens by itself (or open **Ubuntu** from the Start
   menu). Wait for it to unpack, then choose a username and a password. The password does not show while you
   type: that is normal. Remember it: `sudo` asks for it.

3. **Check WSL**, in PowerShell (not admin is fine):

   ```
   PS> wsl --version
   PS> wsl -l -v
   ```

   The first line of `wsl --version` is `WSL version:` followed by a number, which must be 2.1.5 or newer.
   If it is older, or no version appears at all, run `wsl --update` (admin PowerShell). `wsl -l -v` lists
   Ubuntu; its `VERSION` column must say `2`. If it says `1`: `wsl --set-version Ubuntu 2`.

4. **Docker Desktop.** Download the Windows installer from
   https://docs.docker.com/desktop/setup/install/windows-install/ and run `Docker Desktop Installer.exe`.
   On the configuration page choose **WSL 2** ("Use WSL 2 instead of Hyper-V"). When it finishes, start
   Docker Desktop from the Start menu and accept the agreement.

   Then Docker Desktop > **Settings** > **Resources** > **WSL Integration**: make sure the switch for
   **Ubuntu** is on, click **Apply**. If WSL Integration is missing, Docker is in Windows-container
   mode: right-click the whale in the taskbar > **Switch to Linux containers**.

5. **Tools inside Ubuntu.** Open the Ubuntu app. From now on every command runs here:

   ```
   $ sudo apt update
   $ sudo apt install -y git make python3
   $ git config --global core.autocrlf input
   ```

   The last line stops git from turning Linux line endings into Windows ones (`\r\n`), which breaks shell
   and Python scripts with errors like `/usr/bin/env: 'python3\r': No such file or directory`.

6. **Work in the Linux home directory**, never under `/mnt/c/...`. Microsoft: "For the fastest performance
   speed, store your files in the WSL file system if you are working in a Linux command line"
   (learn.microsoft.com/windows/wsl/filesystems). Docker agrees: "avoid `docker run -v /mnt/c/users:/users`".
   So always start with:

   ```
   $ cd ~
   $ pwd
   /home/<your-linux-user>
   ```

   Don't clone with Git for Windows or GitHub Desktop into `C:\...`: clone inside Ubuntu (section 5).

7. **Memory.** With WSL2, Docker's memory is WSL's memory, which defaults to "50% of total memory on
   Windows" (learn.microsoft.com/windows/wsl/wsl-config). 16 GB laptop: nothing to do. 8 GB laptop: you get
   4 GB; close other apps while jobs run (the WordCount job below peaked at 2.0 GB). To give WSL 6 GB on a 12 GB+ laptop, create
   `C:\Users\<you>\.wslconfig` in Notepad with

   ```
   [wsl2]
   memory=6GB
   ```

   then run `wsl --shutdown` in PowerShell and restart Docker Desktop.

Continue with section 3, in the Ubuntu app.

## 2C. Linux (Ubuntu or Debian)

Use Docker Engine from Docker's own repository, not the `docker.io` package of your distribution. Supported
(docs.docker.com/engine/install/ubuntu, /debian, 2026-11-01): Ubuntu 26.10, 26.04 LTS, 24.04 LTS, 22.04 LTS;
Debian 13 (trixie) and 12 (bookworm). The commands below are Docker's, for Ubuntu; on Debian replace both
`linux/ubuntu` by `linux/debian` and use `$VERSION_CODENAME` as the suite.

1. Remove conflicting packages (apt may say none are installed):

   ```
   $ sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1)
   ```

2. Add Docker's repository:

   ```
   $ sudo apt update
   $ sudo apt install ca-certificates curl
   $ sudo install -m 0755 -d /etc/apt/keyrings
   $ sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
   $ sudo chmod a+r /etc/apt/keyrings/docker.asc
   $ sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
   Types: deb
   URIs: https://download.docker.com/linux/ubuntu
   Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
   Components: stable
   Architectures: $(dpkg --print-architecture)
   Signed-By: /etc/apt/keyrings/docker.asc
   EOF
   $ sudo apt update
   ```

3. Install Docker Engine, the Compose plugin and the tools:

   ```
   $ sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   $ sudo apt install -y git make python3
   ```

4. Run Docker without `sudo` (docs.docker.com/engine/install/linux-postinstall):

   ```
   $ sudo groupadd docker          # "already exists" is fine
   $ sudo usermod -aG docker $USER
   ```

   Log out and back in (or reboot), so the new group applies. `newgrp docker` applies it to the current
   terminal only. Membership in the `docker` group is equivalent to root access on this machine.

Docker Engine has no memory limit of its own: containers can use all of the machine's RAM. Continue with
section 3.

## 3. Check Docker (everyone)

```
$ docker version
Client:
 Version:           29.9.2
 ...
Server: Docker Desktop 4.97.0 (244584)
 Engine:
  Version:          29.9.2
  ...
  OS/Arch:          linux/arm64
```

You must see **both** a `Client:` and a `Server:` section. `Cannot connect to the Docker daemon` means Docker
is not running: start Docker Desktop (or `sudo systemctl start docker` on Linux) and wait for it.

```
$ docker compose version
Docker Compose version v5.6.1
```

Any version 2 or newer works; `docker-compose` (with a dash) is the old tool and not what we use.

```
$ docker run --rm hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
...
Hello from Docker!
This message shows that your installation appears to be working correctly.
```

```
$ docker info | grep "Total Memory"
 Total Memory: 11.67GiB
```

That's the memory Docker can use (11.67 GiB on the instructor's machine): it should be about 4 GiB or more.

## 4. git and GitHub

1. Create a free account at https://github.com/signup if you don't have one. Your **username** (top-right
   menu on github.com) is what the course asks for in the Moodle form, not your email.
2. Tell git who you are, once per computer (on Windows: inside Ubuntu):

   ```
   $ git config --global user.name "Your Name"
   $ git config --global user.email "you@example.com"
   ```

3. Cloning the cluster (section 5) needs no login. Your private recitation and homework repositories will.
   GitHub does not accept your account password in `git`; log in once with the GitHub CLI:
   install it from https://cli.github.com (Ubuntu and WSL: `sudo apt install -y gh`), then

   ```
   $ gh auth login
   ```

   and answer: GitHub.com, HTTPS, "Login with a web browser".

## 5. Get the cluster and run a first job

```
$ cd ~
$ git clone https://github.com/bigdata-management-course/hadoop-cluster.git
$ cd hadoop-cluster
$ ls
conf			INSTALL.md		wordcount-java
data			Makefile		wordcount-python
docker-compose.yml	README.md
Dockerfile		TUTORIAL.md
```

All `make` commands run in this `hadoop-cluster` directory.

**Start the cluster.** The first time this builds the Hadoop image (it downloads Ubuntu packages and the 494 MB
Hadoop release; on a fast line under a minute, on a slow one 10-15 minutes), then starts six containers and
waits until each one reports healthy (about 20 s):

```
$ make up
...
docker compose ps
NAME                           IMAGE                      COMMAND                  SERVICE           CREATED          STATUS                    PORTS
hadoop-lab-datanode1-1         bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   datanode1         17 seconds ago   Up 11 seconds (healthy)
hadoop-lab-datanode2-1         bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   datanode2         17 seconds ago   Up 11 seconds (healthy)
hadoop-lab-historyserver-1     bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   historyserver     17 seconds ago   Up 11 seconds (healthy)   127.0.0.1:19888->19888/tcp
hadoop-lab-namenode-1          bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   namenode          17 seconds ago   Up 17 seconds (healthy)   127.0.0.1:9870->9870/tcp
hadoop-lab-nodemanager-1       bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   nodemanager       17 seconds ago   Up 5 seconds (healthy)
hadoop-lab-resourcemanager-1   bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   resourcemanager   17 seconds ago   Up 11 seconds (healthy)   127.0.0.1:8088->8088/tcp
```

All six must say `(healthy)`. Open the web UIs in your browser: http://localhost:9870 (HDFS NameNode, the
*Datanodes* tab lists 2 live nodes), http://localhost:8088 (YARN), http://localhost:19888 (finished jobs).

**Build the WordCount jar.** If you have no Maven installed (most of you), this runs Maven in a container; the
first time it downloads the Maven image (220 MB) and the Hadoop client libraries (40 MB, kept in `~/.m2`).
It prints nothing when it works:

```
$ make jar
$ ls wordcount-java/target/wordcount.jar
wordcount-java/target/wordcount.jar
```

**Copy the three books into HDFS:**

```
$ make put-data
...
Found 3 items
-rw-r--r--   2 hadoop supergroup    1234550 2026-11-01 11:50 input/moby-dick.txt
-rw-r--r--   2 hadoop supergroup     737950 2026-11-01 11:50 input/pride-and-prejudice.txt
-rw-r--r--   2 hadoop supergroup    5422627 2026-11-01 11:50 input/shakespeare.txt
```

**Run WordCount on the cluster** (about 20 s):

```
$ make java
...
2026-11-01 11:50:51,995 INFO mapreduce.JobSubmitter: number of splits:5
...
2026-11-01 11:51:07,664 INFO mapreduce.Job:  map 100% reduce 100%
2026-11-01 11:51:07,671 INFO mapreduce.Job: Job job_1793533827817_0001 completed successfully
...
--- top 10 words (Java) ---
the	49594
and	38721
to	30047
of	29224
i	28450
a	23275
in	18708
that	17003
you	16924
my	14521
```

Your job ID differs; the ten words and counts must be exactly these. **Done: your laptop runs Hadoop.**

**Stop the cluster** when you are finished:

```
$ make down
```

This stops the six containers and erases HDFS (it lives inside them). The image and the jar stay, so the next
`make up` takes about 20 s and needs no download. Run `make put-data` again after each `make up`.

Next: [TUTORIAL.md](TUTORIAL.md), the Lab 3 walkthrough on this cluster.

## 6. If something fails

| Symptom | Cause and fix |
|---|---|
| Windows: `0x80370102`, "virtual machine could not be started", or Docker says virtualization is off | Hardware virtualization is disabled in the BIOS/UEFI. Microsoft: "Please make sure that virtualization is enabled inside of your computer's BIOS". Reboot into the BIOS (the key depends on the maker, often F2, F10, Del or Esc at power-on) and turn on Intel VT-x / AMD-V / SVM. |
| Windows: Docker Desktop says WSL is too old, or `wsl --version` prints nothing | `wsl --update` in an admin PowerShell, then restart Docker Desktop. |
| Windows: `docker: command not found` inside Ubuntu | Docker Desktop is not running, or WSL Integration for Ubuntu is off (2B step 4). |
| `/usr/bin/env: 'python3\r'` or `$'\r': command not found` | The files were checked out with Windows line endings. Inside Ubuntu: `git config --global core.autocrlf input`, delete the folder, clone again in `~`. |
| Everything is very slow on Windows | You are under `/mnt/c/...`. Clone again in `~` (2B step 6). |
| Linux: `permission denied while trying to connect to the Docker daemon socket` | You are not in the `docker` group yet: 2C step 4, then log out and in. |
| `Cannot connect to the Docker daemon` | Docker is not running: start Docker Desktop and wait for "Engine running". |
| `make up`: `bind: address already in use` / `port is already allocated` for 9870, 8088 or 19888 | Another program, or an old cluster, holds the port. First try `make down`. Otherwise find it: `lsof -i :8088` (macOS/Linux) and stop it. |
| `make up` ends with `container ... is unhealthy`, or containers exit with code 137 | Docker is short of memory. Close other apps and containers (`docker ps`), raise Docker's memory (2A step 4 / 2B step 7), then `make down` and `make up`. `docker compose logs namenode \| tail -30` shows what a container said. |
| `make java` hangs at `map 0%` or the job stays `ACCEPTED` | Same memory problem, or the disk is almost full (the NodeManager refuses work above 99%). Free disk space; `docker system df` shows what Docker holds. |
| Image build fails with a `curl` or download error | The Apache mirror refused or the network dropped. Run `make up` again: it continues where it stopped, and falls back to archive.apache.org. |
| `make jar` fails with a network error | Retry on a better connection; what was downloaded stays in `~/.m2`. |
| University or company network blocks downloads, or a proxy/VPN breaks Docker | Do sections 2-5 at home. On a VPN, disconnect it while downloading. |
| Apple Silicon: warnings about `platform linux/amd64` | Something forced an Intel image. Our image is native arm64; don't add `platform: linux/amd64` anywhere, and delete the image (`docker image rm bigdata-lab/hadoop:3.4.1`) and `make up` again. |
| `no space left on device` | Free disk space. `docker system prune` removes stopped containers, unused networks, dangling images and build cache of *all* your Docker projects: read its warning before you confirm. |

Still stuck? Post the exact command and the last 20 lines it printed on the Moodle forum, or come to the
practice session 10 minutes early.

## Appendix: no download possible (offline image)

If the image build is impossible on your connection, the instructor can give you the built image as a file
(USB stick or a local share). There are two files: `arm64` for Apple Silicon, `amd64` for everything else
(Intel Macs, Windows, most Linux laptops). Check with `uname -m` (`arm64`/`aarch64` vs `x86_64`). Then, in
`hadoop-cluster`:

```
$ docker load -i hadoop-image-<arch>.tar.gz
Loaded image: bigdata-lab/hadoop:3.4.1
$ docker compose up -d --no-build --wait
```

`--no-build` uses the loaded image as it is. Then `make put-data` and continue as in section 5. `make jar`
still needs about 260 MB once; do it on any working connection before the next session.
