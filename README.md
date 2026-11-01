# Lab 3: Hadoop on your laptop

In about an hour you will start a small Hadoop cluster in Docker, store files in
HDFS, run WordCount as a Java MapReduce job and as a Python Streaming job, measure
what a combiner saves, and kill a datanode to watch HDFS repair itself.

```
  HDFS (storage)                          YARN (compute)
  namenode      :9870  metadata           resourcemanager :8088  schedules jobs
  datanode1/2          block replicas     nodemanager            runs map/reduce tasks
  datanode3            spare (step 8)     historyserver   :19888 finished jobs
```

Everything runs from this directory. The `Makefile` wraps the long
commands; each step below also shows the raw command so you can see what it does.

## 0. Prerequisites (5 min, do this before class)

Step by step for macOS, Windows (WSL2) and Linux, with the expected output: [INSTALL.md](INSTALL.md).
The lab itself, step by step with what happens inside and the expected output: [TUTORIAL.md](TUTORIAL.md).

- Docker Desktop (macOS/Windows) or Docker Engine + Compose v2 (Linux).
  Give Docker **at least 6 GB of memory** (Docker Desktop > Settings > Resources).
- `make` and `bash`. On Windows, work inside WSL2 (Ubuntu).
- Optional: JDK 11+ and Maven. Without them, `make java` builds the jar in a Maven container.
- About 2.5 GB free disk for images.

Build the image once (it downloads Hadoop 3.4.1, ~500 MB, so do it on good Wi-Fi):

```sh
docker compose build
make jar    # also before class: first Maven run downloads dependencies
```

Why not the official `apache/hadoop` image? It is published for amd64 only and would run
under emulation on Apple Silicon. The `Dockerfile` here installs the same Apache release on
`eclipse-temurin:11` (Java 11), which exists for both amd64 and arm64.

## 1. Start the cluster (5 min)

```sh
make up          # = docker compose up -d --build --wait
```

`--wait` returns once every container passes its health check (about 20 s):

```
NAME                           SERVICE           STATUS                    PORTS
hadoop-lab-datanode1-1         datanode1         Up 11 seconds (healthy)
hadoop-lab-datanode2-1         datanode2         Up 10 seconds (healthy)
hadoop-lab-historyserver-1     historyserver     Up 11 seconds (healthy)   127.0.0.1:19888->19888/tcp
hadoop-lab-namenode-1          namenode          Up 16 seconds (healthy)   127.0.0.1:9870->9870/tcp
hadoop-lab-nodemanager-1       nodemanager       Up 5 seconds (healthy)
hadoop-lab-resourcemanager-1   resourcemanager   Up 11 seconds (healthy)   127.0.0.1:8088->8088/tcp
```

Configuration lives in `conf/*-site.xml` (mounted into every container). Open
`conf/hdfs-site.xml`: replication is 2 and the block size is a tiny **2 MB**, so our
few-MB books are split into several blocks, just like a 10 GB file would be with the
default 128 MB.

## 2. HDFS basics (10 min)

Open a shell on the namenode. HDFS commands run there; the lab directory is mounted at `/lab`.

```sh
docker compose exec namenode bash
```

```sh
hdfs dfs -ls /                       # empty at first
hdfs dfs -mkdir -p input             # relative paths live under /user/hadoop
hdfs dfs -put /lab/data/*.txt input/
hdfs dfs -ls input
```

```
Found 3 items
-rw-r--r--   2 hadoop supergroup    1234550 2026-10-18 01:30 input/moby-dick.txt
-rw-r--r--   2 hadoop supergroup     737950 2026-10-18 01:30 input/pride-and-prejudice.txt
-rw-r--r--   2 hadoop supergroup    5422627 2026-10-18 01:30 input/shakespeare.txt
```

The `2` in the second column is the replication factor. Read a file back:

```sh
hdfs dfs -cat input/moby-dick.txt | grep -m1 Ishmael
hdfs dfs -du -h input
```

Now ask the namenode where the blocks actually are:

```sh
hdfs fsck /user/hadoop/input -files -blocks -locations
```

```
/user/hadoop/input/shakespeare.txt 5422627 bytes, replicated: replication=2, 3 block(s):  OK
0. BP-...:blk_1073741827_1003 len=2097152 Live_repl=2  [DatanodeInfoWithStorage[172.30.0.5:9866,...], DatanodeInfoWithStorage[172.30.0.3:9866,...]]
1. BP-...:blk_1073741828_1004 len=2097152 Live_repl=2  [...]
2. BP-...:blk_1073741829_1005 len=1228323 Live_repl=2  [...]
Status: HEALTHY
 Number of data-nodes:  2
 Total blocks (validated):  5 (avg. block size 1479025 B)
 Under-replicated blocks:   0 (0.0 %)
 Average block replication: 2.0
```

Shakespeare (5.4 MB) became 3 blocks of at most 2 MB, each stored on both datanodes.
`exit` the shell when done. (`make put-data` does the mkdir/put in one go.)

**Question:** with 3 datanodes and replication 2, what fraction of the cluster could you
lose without losing data?

## 3. Look at the web UIs (5 min)

| UI | URL | Look for |
|---|---|---|
| HDFS NameNode | http://localhost:9870 | *Datanodes* tab (2 live), *Utilities > Browse the file system* (click a file to see its blocks) |
| YARN ResourceManager | http://localhost:8088 | *Nodes* (1 nodemanager, 2048 MB), *Applications* after you run a job |
| MapReduce Job History | http://localhost:19888 | finished jobs, their counters and task timelines |

Links that point at `nodemanager:8042` or a datanode (task logs, file downloads) use
container hostnames and won't open from your browser. That's expected.

## 4. Java WordCount (10 min)

Code: `wordcount-java/src/main/java/edu/univ/haifa/bigdata/`

| Class | Role |
|---|---|
| `TokenizerMapper` | line -> `(word, 1)` for each run of letters, lowercased |
| `IntSumReducer` | `(word, [1,1,...])` -> `(word, sum)`; also used as the **combiner** |
| `AlphabetPartitioner` | sends words to reducers by first letter, so with 2 reducers `part-r-00000` holds a..m and `part-r-00001` n..z |
| `WordCount` | driver: wires the classes into a `Job`; `-D wordcount.combiner=false` turns the combiner off |

```sh
make java
```

which runs

```sh
mvn -q -f wordcount-java/pom.xml package       # -> wordcount-java/target/wordcount.jar
docker compose exec namenode hdfs dfs -rm -r -f -skipTrash out-java
docker compose exec namenode hadoop jar /lab/wordcount-java/target/wordcount.jar \
    -D mapreduce.job.reduces=2 input out-java
```

Expected (abridged):

```
INFO input.FileInputFormat: Total input files to process : 3
INFO mapreduce.JobSubmitter: number of splits:5
INFO mapreduce.Job: Running job: job_1792287002397_0001
INFO mapreduce.Job:  map 0% reduce 0%
INFO mapreduce.Job:  map 60% reduce 0%
INFO mapreduce.Job:  map 100% reduce 50%
INFO mapreduce.Job:  map 100% reduce 100%
INFO mapreduce.Job: Job job_1792287002397_0001 completed successfully
        Launched map tasks=5
        Launched reduce tasks=2
        Map output records=1336289
        Combine input records=1336289
        Combine output records=68941
        Reduce input records=68941
        Reduce output records=32971
--- top 10 words (Java) ---
the     49594
and     38721
to      30047
of      29224
i       28450
a       23275
in      18708
that    17003
you     16924
my      14521
```

5 splits = 5 blocks = 5 map tasks. Check the partitioner did its job:

```sh
docker compose exec namenode hdfs dfs -ls out-java
docker compose exec namenode sh -c 'hdfs dfs -cat out-java/part-r-00001 | head -3'   # starts at "n"
```

While it runs, refresh http://localhost:8088 to watch the application move through
ACCEPTED -> RUNNING -> FINISHED.

## 5. Python with Hadoop Streaming (10 min)

Streaming runs any program that reads lines on stdin and writes `key<TAB>value` lines on
stdout. Hadoop sorts the mapper output by key between the two stages, exactly like
`sort` does here. Test locally first:

```sh
cd wordcount-python
printf 'The cat. the DOG, the cat!\nDog\n' | ./mapper.py | sort | ./reducer.py
cat ../data/*.txt | ./mapper.py | sort | ./reducer.py | sort -k2,2nr | head -5
cd ..
```

```
cat     2
dog     2
the     3
```

Then on the cluster:

```sh
make python
```

which runs

```sh
docker compose exec namenode mapred streaming -D mapreduce.job.reduces=2 \
  -files /lab/wordcount-python/mapper.py,/lab/wordcount-python/reducer.py \
  -mapper "python3 mapper.py" -combiner "python3 reducer.py" -reducer "python3 reducer.py" \
  -input input -output out-python
```

It prints the same top 10 as the Java job.

## 6. Compare the outputs (2 min)

```sh
make compare
```

```
diff <(... hdfs dfs -cat 'out-java/part-*' | LC_ALL=C sort) <(... hdfs dfs -cat 'out-python/part-*' | LC_ALL=C sort)
OK: Java and Python outputs are identical
```

Both produce 32,971 distinct words. We sort before diffing because Streaming uses
default hash partitioning, so its words land in different part files than Java's.

## 7. The combiner experiment (5 min)

A combiner is a mini-reducer that runs on the map side, so each map task ships
`(the, 812)` once instead of `(the, 1)` 812 times.

```sh
make combiner-demo
```

```
counter                    with combiner         without
Map output records               1336289         1336289
Combine input records            1336289               0
Combine output records             68941               0
Reduce shuffle bytes              970615        14930222
Reduce input records               68941         1336289
```

The combiner cut the data moved over the network in the shuffle by about **15x**
(0.97 MB vs 14.9 MB) and the reducers' input from 1.3 M records to 69 K.

**Questions:** why is it safe to reuse `IntSumReducer` as a combiner? Would it be safe
for a job computing the *average* word length? (Hint: is average associative?)

## 8. Fault tolerance: kill a datanode (10 min)

Simulate a crashed machine:

```sh
docker compose kill datanode2
```

The namenode marks a datanode dead after missing heartbeats: ~60 s here (shortened in
`hdfs-site.xml`; the default is 10.5 minutes), and drops its replicas from the block map a few
seconds later. Poll until it shows up:

```sh
docker compose exec namenode hdfs dfsadmin -report -dead
```

```
Dead datanodes (1):
Name: 172.30.0.3:9866 (172.30.0.3)
Last contact: Sun Oct 18 01:25:23 UTC 2026
```

```sh
docker compose exec namenode hdfs fsck /user/hadoop/input -files -blocks -locations
```

```
0. BP-...:blk_1073741825_1001 len=1234550 Live_repl=1  [DatanodeInfoWithStorage[172.30.0.5:9866,...]]
Status: HEALTHY
 Under-replicated blocks:   5 (100.0 %)
 Average block replication: 1.0
 Missing blocks:            0
```

Every block now has only one copy, yet nothing is lost and files still read fine
(`hdfs dfs -cat input/moby-dick.txt | head`). But with 2 datanodes and replication 2
there is **nowhere to put a second copy**, so HDFS waits. Add a fresh machine:

```sh
docker compose --profile spare up -d --wait datanode3
while sleep 3; do docker compose exec namenode hdfs fsck /user/hadoop/input | grep -E 'Under-replicated|Average block'; done   # Ctrl-C to stop
```

Within ~40 s the namenode copies every block from datanode1 to datanode3:

```
 Under-replicated blocks:   0 (0.0 %)
 Average block replication: 2.0
```

`hdfs dfsadmin -report -live` now lists `datanode1` and `datanode3`. Docker may give
datanode3 the IP address datanode2 used, so go by the `Hostname:` lines rather than IPs.

Bonus: `docker compose start datanode2`. It comes back with its old replicas, so some blocks
briefly have 3 copies; the namenode deletes the excess within seconds. In
`hdfs dfsadmin -report -live`, one datanode's `DFS Used` drops to almost zero. Which one
it is depends on the namenode's choice of which replica to remove.

## 9. Tear down (1 min)

```sh
make down        # = docker compose --profile spare down -v --remove-orphans
```

HDFS data lives inside the containers, so this wipes it; next `make up` starts with a
freshly formatted, empty HDFS. `docker image rm bigdata-lab/hadoop:3.4.1` frees the 1.1 GB image.

## Troubleshooting

**Port already in use** (`bind: address already in use` for 9870, 8088 or 19888): something
else is listening. Find it with `lsof -i :8088` (macOS/Linux), or change the left side
of the mapping in `docker-compose.yml`, e.g. `"18088:8088"`.

**Containers exit with code 137, or jobs hang in ACCEPTED**: Docker is out of memory.
The cluster needs ~2 GB while a job runs (limits add up to 5.5 GB). Raise Docker's memory
to 6+ GB, close other containers (`docker stats` shows who uses what), and check
http://localhost:8088/cluster/nodes shows one healthy node with 2048 MB.

**Node shows UNHEALTHY / jobs stay ACCEPTED forever**: usually a nearly full disk. We
already raised the threshold to 99%; free some disk space or run `docker system df`.

**Apple Silicon (arm64)**: the image is native arm64; nothing is emulated. You'll see no
native-library warning because we silenced it: Hadoop has no arm64 native libs in this
tarball and falls back to pure Java, which is fine for this lab. Don't add
`platform: linux/amd64`; emulated Java is much slower.

**`make up` fails with `container ... is unhealthy`**: look at that container's log,
e.g. `docker compose logs resourcemanager | tail -50`. Then `make down && make up`.

**`Output directory ... already exists`**: MapReduce never overwrites output. The make
targets delete it first; when running by hand use `hdfs dfs -rm -r -f out-java`.

**`mvn` errors about the release version**: your local JDK is older than 11. Install JDK 11+,
or take `mvn` off your PATH so `make java` builds in a Maven container instead.

**Windows line endings**: if `./mapper.py` fails with `env: python3\r`, your checkout
converted the scripts to CRLF. Run `dos2unix wordcount-python/*.py`.
