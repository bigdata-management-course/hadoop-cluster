# Lab 3 tutorial: Hadoop on your laptop, step by step

This walks you through the lab one step at a time. You start the cluster, store the books in HDFS and read
back where their blocks are, then run WordCount twice, as Java MapReduce and as Python Streaming. After that
you measure what the combiner saves, and finally kill a DataNode and watch HDFS repair itself. About an hour.

Every output below was produced by these exact commands on a clean clone of this repository on 1 November
2026, on a Mac with Apple Silicon. Your output will show other timestamps, job IDs and IP addresses; every
count and byte size must match. `...` marks lines left out of long outputs.
In that session steps 5-7 ran after step 8, with three DataNodes up; their numbers do not depend on it.

Before you start: section 1-5 of [INSTALL.md](INSTALL.md) (Docker works, image built, `make jar` done).
All commands run in the `hadoop-cluster` directory.

```
  HDFS (storage)                          YARN (compute)
  namenode      :9870  metadata           resourcemanager :8088  schedules jobs
  datanode1/2          block replicas     nodemanager            runs map/reduce tasks
  datanode3            spare (step 8)     historyserver   :19888 finished jobs
```

| Step | What you do | Minutes |
|---|---|---|
| 1 | start the cluster | 5 |
| 2 | put the books into HDFS, look at the blocks | 10 |
| 3 | the three web UIs | 5 |
| 4 | WordCount in Java | 10 |
| 5 | WordCount in Python (Streaming) | 10 |
| 6 | compare the two outputs | 2 |
| 7 | the combiner experiment | 5 |
| 8 | kill a DataNode, watch HDFS heal | 10 |
| 9 | tear down | 1 |

---

## Step 1. Start the cluster

**Command**

```
$ make up
```

`make up` runs `docker compose up -d --build --wait`, then `docker compose ps`.

**What happens inside.** Compose creates one network and six containers from one image
(`bigdata-lab/hadoop:3.4.1`). Each container runs one Hadoop daemon: the `command:` of its service in
`docker-compose.yml`. The NameNode formats an empty HDFS on its first start. The order comes from
`depends_on: condition: service_healthy`:

1. the NameNode starts first;
2. once its web page answers, the DataNodes, the ResourceManager and the history server start;
3. the NodeManager waits for the ResourceManager.

`--wait` returns only when every container's health check (a `curl` on its web port, every 5 s) passes.
The configuration in `conf/*-site.xml` is mounted into every container. Open `conf/hdfs-site.xml`:
replication is 2 and the block size is **2 MB**, so a 5 MB book is split the way a 10 GB file would be with
the default 128 MB blocks.

**Expected output**

```
docker compose up -d --build --wait
...
docker compose ps
NAME                           IMAGE                      COMMAND                  SERVICE           CREATED          STATUS                    PORTS
hadoop-lab-datanode1-1         bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   datanode1         17 seconds ago   Up 11 seconds (healthy)
hadoop-lab-datanode2-1         bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   datanode2         17 seconds ago   Up 10 seconds (healthy)
hadoop-lab-historyserver-1     bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   historyserver     17 seconds ago   Up 11 seconds (healthy)   127.0.0.1:19888->19888/tcp
hadoop-lab-namenode-1          bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   namenode          17 seconds ago   Up 16 seconds (healthy)   127.0.0.1:9870->9870/tcp
hadoop-lab-nodemanager-1       bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   nodemanager       17 seconds ago   Up 5 seconds (healthy)
hadoop-lab-resourcemanager-1   bigdata-lab/hadoop:3.4.1   "/__cacert_entrypoin…"   resourcemanager   17 seconds ago   Up 11 seconds (healthy)   127.0.0.1:8088->8088/tcp

real	0m19.373s
```

The uptimes show the start order: namenode 16 s, the next four 10-11 s, nodemanager 5 s.

**Check.** Six lines, each `(healthy)`. The spare `datanode3` is not there; it starts only in step 8.

**Common mistakes**

- `container ... is unhealthy` or exit code 137: Docker has too little memory (INSTALL.md section 6).
  `docker compose logs namenode | tail -30` shows what a daemon said.
- `port is already allocated`: an old cluster or another program holds 9870, 8088 or 19888. `make down`,
  then `make up`.

---

## Step 2. HDFS: put the books in, look at the blocks

**Commands.** HDFS commands run inside the namenode container, where the `hdfs` client is installed. This
directory is mounted there read-only at `/lab`.

```
$ docker compose exec -T namenode hdfs dfs -ls /
$ docker compose exec -T namenode hdfs dfs -mkdir -p input
$ docker compose exec -T namenode sh -c 'hdfs dfs -put /lab/data/*.txt input/'
$ docker compose exec -T namenode hdfs dfs -ls input
```

(`make put-data` does the last three in one go.) For an interactive shell instead:
`docker compose exec namenode bash`, then `hdfs dfs ...` directly, `exit` to leave.

**What happens inside.** For each file, the client asks the NameNode where to write. The NameNode picks two
DataNodes per block (replication 2). The client streams each 2 MB block to the first DataNode, which forwards
it to the second. The NameNode only stores metadata: file names, block IDs and which DataNodes hold each
block. `input` is a relative path, so it means `/user/hadoop/input` (the containers run as user `hadoop`).

**Expected output**

```
$ docker compose exec -T namenode hdfs dfs -ls /
Found 1 items
drwxrwx---   - hadoop supergroup          0 2026-11-01 12:27 /tmp
$ docker compose exec -T namenode hdfs dfs -ls input
Found 3 items
-rw-r--r--   2 hadoop supergroup    1234550 2026-11-01 12:27 input/moby-dick.txt
-rw-r--r--   2 hadoop supergroup     737950 2026-11-01 12:27 input/pride-and-prejudice.txt
-rw-r--r--   2 hadoop supergroup    5422627 2026-11-01 12:27 input/shakespeare.txt
```

The `2` in the second column is the replication factor. Read a file back, and see the space it takes:

```
$ docker compose exec -T namenode hdfs dfs -cat input/moby-dick.txt | grep -m1 Ishmael
Call me Ishmael. Some years ago—never mind how long precisely—having
$ docker compose exec -T namenode hdfs dfs -du -h input
1.2 M    2.4 M   input/moby-dick.txt
720.7 K  1.4 M   input/pride-and-prejudice.txt
5.2 M    10.3 M  input/shakespeare.txt
```

`-du` prints two sizes per file: the file itself, and the disk space all its replicas use, twice as much.

Now ask the NameNode where the blocks are:

```
$ docker compose exec -T namenode hdfs fsck /user/hadoop/input -files -blocks -locations
...
/user/hadoop/input/moby-dick.txt 1234550 bytes, replicated: replication=2, 1 block(s):  OK
0. BP-919096361-172.31.0.2-1793536043475:blk_1073741825_1001 len=1234550 Live_repl=2  [DatanodeInfoWithStorage[172.31.0.5:9866,...,DISK], DatanodeInfoWithStorage[172.31.0.6:9866,...,DISK]]

/user/hadoop/input/pride-and-prejudice.txt 737950 bytes, replicated: replication=2, 1 block(s):  OK
0. BP-919096361-172.31.0.2-1793536043475:blk_1073741826_1002 len=737950 Live_repl=2  [...]

/user/hadoop/input/shakespeare.txt 5422627 bytes, replicated: replication=2, 3 block(s):  OK
0. BP-919096361-172.31.0.2-1793536043475:blk_1073741827_1003 len=2097152 Live_repl=2  [...]
1. BP-919096361-172.31.0.2-1793536043475:blk_1073741828_1004 len=2097152 Live_repl=2  [...]
2. BP-919096361-172.31.0.2-1793536043475:blk_1073741829_1005 len=1228323 Live_repl=2  [...]

Status: HEALTHY
 Number of data-nodes:	2
...
 Total blocks (validated):	5 (avg. block size 1479025 B)
 Minimally replicated blocks:	5 (100.0 %)
 Over-replicated blocks:	0 (0.0 %)
 Under-replicated blocks:	0 (0.0 %)
...
 Average block replication:	2.0
 Missing blocks:		0
```

Read it line by line:

- Shakespeare (5,422,627 bytes) became 3 blocks. Two are full (2,097,152 bytes = 2 MB), and the last holds
  the remaining 1,228,323 bytes.
- The other two books fit into one block each, so there are 5 blocks in all.
- `Live_repl=2`: every block is on both DataNodes (two `DatanodeInfoWithStorage[...]` entries, the
  DataNodes' container IPs).

`hdfs dfsadmin -report` shows the same from the DataNodes' side: `Live datanodes (2)`, then for each
`Hostname: datanode1` / `datanode2` and `Num of Blocks: 5`.

**Check.** Three files with exactly these sizes; `fsck` says `HEALTHY`, `Total blocks (validated): 5`,
`Average block replication: 2.0`.

**Common mistakes**

- ``put: `input/moby-dick.txt': File exists``: you ran `-put` twice. `-put -f` overwrites.
- Running `hdfs` on your laptop instead of with `docker compose exec -T namenode ...`: `command not found`.
- `No such file or directory` for `/lab/data`: you are not in the `hadoop-cluster` directory, or you changed
  the mount in `docker-compose.yml`.

**Question.** With 3 DataNodes and replication 2, what fraction of the cluster could you lose without losing
data?

---

## Step 3. The three web UIs

Open them in your browser:

| UI | URL | Look for |
|---|---|---|
| HDFS NameNode | http://localhost:9870 | *Datanodes* tab: 2 live nodes, 5 blocks each; *Utilities > Browse the file system* > `/user/hadoop/input` > click a file: its blocks and where they live |
| YARN ResourceManager | http://localhost:8088 | *Nodes*: one NodeManager, `RUNNING`, 2 GB; *Applications* after step 4 |
| MapReduce Job History | http://localhost:19888 | finished jobs, their counters and task times (after step 4) |

**What happens inside.** Each daemon serves its own web page on its own port. Compose publishes only these
three ports, and only on `127.0.0.1`, so nobody else on your network can reach them. The pages show the
same facts the command-line tools report. The same numbers, read from the REST interfaces in my run:

```
$ curl -s 'http://localhost:9870/jmx?qry=Hadoop:service=NameNode,name=FSNamesystemState' | grep -E 'NumLiveDataNodes|BlocksTotal|FilesTotal'
    "BlocksTotal" : 5,
    "FilesTotal" : 13,
    "NumLiveDataNodes" : 2,
$ curl -s http://localhost:8088/ws/v1/cluster/nodes
{"nodes":{"node":[{"rack":"/default-rack","state":"RUNNING","id":"nodemanager:37957","nodeHostName":"nodemanager",...,"availMemoryMB":2048,"usedVirtualCores":0,"availableVirtualCores":4,...
```

`FilesTotal` counts directories too (`/tmp`, `/user`, ...), not just the three books. The NodeManager offers
2048 MB and 4 vcores for tasks: `yarn.nodemanager.resource.memory-mb` and `cpu-vcores` in
`conf/yarn-site.xml`.

**Check.** 9870 lists 2 live DataNodes; 8088 lists one node in state `RUNNING`.

**Common mistakes.** Links that point to `nodemanager:8042` or `datanode1:9864` (task logs, file downloads)
do not open: those are container host names, only valid inside the Docker network. That's expected. Use
`http://`, not `https://`.

---

## Step 4. WordCount in Java

**The code** is in `wordcount-java/src/main/java/edu/univ/haifa/bigdata/`:

| Class | Role |
|---|---|
| `TokenizerMapper` | one line in, `(word, 1)` out for every run of letters `a-z`, lowercased |
| `IntSumReducer` | `(word, [1, 1, ...])` in, `(word, sum)` out; also used as the **combiner** |
| `AlphabetPartitioner` | sends a word to a reducer by its first letter: with 2 reducers, `part-r-00000` gets a-m and `part-r-00001` gets n-z |
| `WordCount` | the driver: wires the classes into a `Job`; `-D wordcount.combiner=false` switches the combiner off |

**Command**

```
$ make java
```

which runs (after `make jar`, if the jar is out of date)

```
docker compose exec -T namenode hdfs dfs -rm -r -f -skipTrash out-java
docker compose exec -T namenode hadoop jar /lab/wordcount-java/target/wordcount.jar -D mapreduce.job.reduces=2 input out-java
```

and then prints the ten most frequent words.

**What happens inside**

1. The client (`hadoop jar`, inside the namenode container) asks the NameNode for the blocks of `input/`
   and makes one **input split** per block: 5 splits. It uploads the jar and submits the job to the
   ResourceManager.
2. YARN starts an ApplicationMaster and then the task containers (JVMs) inside the NodeManager's 2 GB:
   5 map tasks, one per split, then 2 reduce tasks because of `mapreduce.job.reduces=2`.
3. Each map task reads its block from a DataNode and emits `(word, 1)` pairs. The combiner sums them per
   map task before they leave the map side.
4. In the **shuffle**, each reducer fetches its partition from every map task (2 reducers × 5 maps =
   10 fetches). It merges them sorted by word, and sums.
5. Each reducer writes one file `part-r-0000N` to HDFS. The history server keeps the finished job.

**Expected output**

```
$ make java
docker compose exec -T namenode hdfs dfs -rm -r -f -skipTrash out-java
docker compose exec -T namenode hadoop jar /lab/wordcount-java/target/wordcount.jar -D mapreduce.job.reduces=2 input out-java
...
2026-11-01 12:27:49,652 INFO mapreduce.JobSubmitter: number of splits:5
2026-11-01 12:27:50,138 INFO impl.YarnClientImpl: Submitted application application_1793536050377_0001
2026-11-01 12:27:50,153 INFO mapreduce.Job: Running job: job_1793536050377_0001
2026-11-01 12:27:54,212 INFO mapreduce.Job:  map 0% reduce 0%
2026-11-01 12:27:59,242 INFO mapreduce.Job:  map 20% reduce 0%
2026-11-01 12:28:00,246 INFO mapreduce.Job:  map 40% reduce 0%
2026-11-01 12:28:01,250 INFO mapreduce.Job:  map 60% reduce 0%
2026-11-01 12:28:02,256 INFO mapreduce.Job:  map 80% reduce 0%
2026-11-01 12:28:03,262 INFO mapreduce.Job:  map 100% reduce 0%
2026-11-01 12:28:04,269 INFO mapreduce.Job:  map 100% reduce 50%
2026-11-01 12:28:05,273 INFO mapreduce.Job:  map 100% reduce 100%
2026-11-01 12:28:05,278 INFO mapreduce.Job: Job job_1793536050377_0001 completed successfully
...
		Launched map tasks=5
		Launched reduce tasks=2
		Rack-local map tasks=5
...
		Map output records=1336289
...
		Combine input records=1336289
		Combine output records=68941
...
		Reduce shuffle bytes=970615
		Reduce input records=68941
		Reduce output records=32971
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

The counters tell the story of the job:

- `number of splits:5` = 5 blocks = `Launched map tasks=5`.
- `Rack-local map tasks=5`: no map ran on a node holding its block. Our only NodeManager runs in its own
  container, without a DataNode, so every block was read over the network.
- 1,336,289 words came out of the maps; the combiner turned them into 68,941 pairs before the shuffle.
- `Reduce output records=32971`: 32,971 distinct words.

Check the partitioner:

```
$ docker compose exec -T namenode hdfs dfs -ls out-java
Found 3 items
-rw-r--r--   2 hadoop supergroup          0 2026-11-01 12:28 out-java/_SUCCESS
-rw-r--r--   2 hadoop supergroup     203428 2026-11-01 12:28 out-java/part-r-00000
-rw-r--r--   2 hadoop supergroup     151268 2026-11-01 12:28 out-java/part-r-00001
$ docker compose exec -T namenode sh -c 'hdfs dfs -cat out-java/part-r-00000 | head -3'
a	23275
aaron	99
aback	2
cat: Unable to write to output stream.
$ docker compose exec -T namenode sh -c 'hdfs dfs -cat out-java/part-r-00001 | head -3'
n	117
nag	2
nags	1
cat: Unable to write to output stream.
```

`part-r-00000` starts at `a`, `part-r-00001` at `n`: the a-m / n-z split. The output is sorted by word
within each file. `cat: Unable to write to output stream.` only means `head` stopped reading after three
lines; it is harmless. `_SUCCESS` is the empty marker the job writes when it finishes.

While a job runs, refresh http://localhost:8088: the application goes from `ACCEPTED` to `RUNNING` to
`FINISHED`. Afterwards it is on http://localhost:19888 as `wordcount`, `SUCCEEDED`, 5 maps, 2 reduces.

**Check.** `completed successfully`, and the top line is `the 49594`.

**Common mistakes**

- `FileAlreadyExistsException: Output directory hdfs://namenode:8020/user/hadoop/... already exists`:
  MapReduce never overwrites output. `make java` deletes `out-java` first; when you run `hadoop jar` by
  hand, run `hdfs dfs -rm -r -f out-java` first.
- `InvalidInputException: Input path does not exist: hdfs://namenode:8020/user/hadoop/input`: you ran
  `make down` and `make up` since step 2, which erased HDFS: `make put-data`.
- The job stays at `map 0%` or `ACCEPTED`: memory or a nearly full disk (INSTALL.md section 6).
- An error about the jar itself: `make jar` failed. Run it alone and read its error.

---

## Step 5. The same job in Python (Hadoop Streaming)

**The code.** `wordcount-python/mapper.py` reads lines on stdin and writes `word<TAB>1` for every run of
letters, using the same rule as `TokenizerMapper`. `wordcount-python/reducer.py` reads lines sorted by word
and writes `word<TAB>sum`. Streaming runs any program that speaks this stdin/stdout protocol.

**Test locally first.** Hadoop sorts the map output by key between the two stages, just like `sort` does
here:

```
$ cd wordcount-python
$ printf 'The cat. the DOG, the cat!\nDog\n' | ./mapper.py | sort | ./reducer.py
cat	2
dog	2
the	3
$ cat ../data/*.txt | ./mapper.py | sort | ./reducer.py | sort -k2,2nr | head -5
the	49594
and	38721
to	30047
of	29224
i	28450
$ cd ..
```

The local pipeline already gives the cluster's answer: the program is the same, only where it runs changes.

**On the cluster**

```
$ make python
```

which runs

```
docker compose exec -T namenode mapred streaming -D mapreduce.job.reduces=2 \
  -files /lab/wordcount-python/mapper.py,/lab/wordcount-python/reducer.py \
  -mapper "python3 mapper.py" -combiner "python3 reducer.py" -reducer "python3 reducer.py" \
  -input input -output out-python
```

**What happens inside.** `-files` ships the two scripts to every task's working directory. Each map task
is a Java process that starts `python3 mapper.py`, feeds it the lines of its split on stdin, and reads
`key<TAB>value` lines back. The framework then does the same sort and shuffle as in step 4. The reducer
script is also the combiner, like `IntSumReducer` in Java.

**Expected output**

```
...
2026-11-01 12:33:13,684 INFO mapreduce.JobSubmitter: number of splits:5
...
2026-11-01 12:33:29,044 INFO mapreduce.Job: Job job_1793536050377_0002 completed successfully
...
		Launched map tasks=5
		Launched reduce tasks=2
...
		Map output records=1336289
...
		Combine input records=1336289
		Combine output records=68941
...
		Reduce shuffle bytes=846162
		Reduce input records=68941
		Reduce output records=32971
...
2026-11-01 12:33:29,096 INFO streaming.StreamJob: Output directory: out-python
--- top 10 words (Python) ---
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

Same records, same top 10. `Reduce shuffle bytes` differs from the Java job (846,162 vs 970,615) because
Streaming moves the pairs as text, while Java uses its binary `Text`/`IntWritable` format. The output files
are named `part-00000`, `part-00001` (no `-r-`):

```
$ docker compose exec -T namenode hdfs dfs -ls out-python
Found 3 items
-rw-r--r--   2 hadoop supergroup          0 2026-11-01 12:33 out-python/_SUCCESS
-rw-r--r--   2 hadoop supergroup     177872 2026-11-01 12:33 out-python/part-00000
-rw-r--r--   2 hadoop supergroup     176824 2026-11-01 12:33 out-python/part-00001
```

The two files are about the same size: without our `AlphabetPartitioner`, Streaming uses the default hash
partitioner, which spreads words over the reducers by a hash, not by letter.

**Check.** `completed successfully` and the same `the 49594`.

**Common mistakes**

- `./mapper.py: Permission denied` locally: the execute bit got lost; `chmod +x wordcount-python/*.py`.
- `/usr/bin/env: 'python3\r'`: Windows line endings (INSTALL.md section 6).
- `PipeMapRed.waitOutputThreads(): subprocess failed with code 2` (or another code): the script failed on
  the cluster. Code 2 is what a misspelled script name gave in my run (`-mapper "python3 nosuch.py"`). Check
  the names after `-files` and `-mapper`, then run the local pipeline above: it shows a Python error
  directly.

---

## Step 6. Compare the two outputs

```
$ make compare
diff <(docker compose exec -T namenode hdfs dfs -cat 'out-java/part-*' | LC_ALL=C sort) \
	     <(docker compose exec -T namenode hdfs dfs -cat 'out-python/part-*' | LC_ALL=C sort)
OK: Java and Python outputs are identical
```

**What happens inside.** Both outputs are read from HDFS, sorted the same way, and compared line by line. We
sort first because the two jobs partition differently (step 5), so the same word lands in different part
files.

**Check.** `OK: Java and Python outputs are identical`. Any `<` / `>` lines show words counted differently;
then the two tokenizers no longer agree.

---

## Step 7. The combiner experiment

A combiner is a mini-reducer that runs on the map side, so a map task ships `(the, 812)` once instead of
`(the, 1)` 812 times. This step runs the Java job twice, with and without it, and puts five counters side
by side.

```
$ make combiner-demo
running wordcount with combiner=true ...
running wordcount with combiner=false ...
counter                    with combiner         without
Map output records               1336289         1336289
Combine input records            1336289               0
Combine output records             68941               0
Reduce shuffle bytes              970615        14930222
Reduce input records               68941         1336289
```

**What happens inside.** The target runs the same jar twice: once as is, once with
`-D wordcount.combiner=false`, where the driver simply does not set a combiner. From each job's counters it
keeps these five lines. Read them in order:

- The maps emit the same 1,336,289 pairs in both runs.
- With the combiner, those pairs enter the combiner and 68,941 come out. Only those cross the network
  (`Reduce shuffle bytes` 970,615) and reach the reducers.
- Without it, all 1,336,289 pairs are shuffled: 14,930,222 bytes, about 15 times as many.

The final output is the same in both runs.

**Check.** Your five rows match these numbers.

**Common mistakes.** Thinking it hangs: it runs two complete jobs (37 s in my run) and prints the table
only at the end, after the two `running wordcount ...` lines.

**Questions.** Why is it safe to reuse `IntSumReducer` as the combiner? Would it be safe in a job that
computes the *average* word length per first letter?

---

## Step 8. Fault tolerance: kill a DataNode

**Simulate a crashed machine**

```
$ docker compose kill datanode2
 Container hadoop-lab-datanode2-1 Killing
 Container hadoop-lab-datanode2-1 Killed
```

**What happens inside.** Every DataNode sends the NameNode a heartbeat every 3 s
(`dfs.heartbeat.interval`). When heartbeats stop, the NameNode waits, then declares the node dead and
drops its replicas from the block map. This cluster shortens the wait to about a minute
(`dfs.namenode.heartbeat.recheck-interval` in `conf/hdfs-site.xml`); the default is 10.5 minutes. Poll
until it happens (my poll every 5 s, local time):

```
$ docker compose exec -T namenode hdfs dfsadmin -report -dead
14:28:12 | Dead datanodes (0):
14:28:17 | Dead datanodes (0):
...
14:29:03 | Dead datanodes (0):
14:29:09 | Dead datanodes (1):
```

About a minute after the kill:

```
$ docker compose exec -T namenode hdfs dfsadmin -report -dead
...
Dead datanodes (1):
Name: 172.31.0.6:9866 (172.31.0.6)
Hostname: datanode2
...
Last contact: Sun Nov 01 12:28:09 UTC 2026
...
Num of Blocks: 0
```

(HDFS prints UTC; my laptop's clock was UTC+2.) Now look at the blocks:

```
$ docker compose exec -T namenode hdfs fsck /user/hadoop/input -files -blocks -locations
...
/user/hadoop/input/moby-dick.txt 1234550 bytes, replicated: replication=2, 1 block(s):  Under replicated BP-...:blk_1073741825_1001. Target Replicas is 2 but found 1 live replica(s), ...
0. BP-919096361-172.31.0.2-1793536043475:blk_1073741825_1001 len=1234550 Live_repl=1  [DatanodeInfoWithStorage[172.31.0.5:9866,...,DISK]]
...
Status: HEALTHY
 Number of data-nodes:	1
 Under-replicated blocks:	5 (100.0 %)
 Average block replication:	1.0
 Missing blocks:		0
```

Every block now has one copy (`Live_repl=1`), but none is missing, so the status is still `HEALTHY`.
Reading still works. In a second run of this step, the client even tried the dead node first, gave up on it,
and read the block from the live replica:

```
$ docker compose exec -T namenode hdfs dfs -cat input/moby-dick.txt | grep -m1 Ishmael
2026-11-01 12:39:40,222 WARN impl.BlockReaderFactory: I/O error constructing remote block reader for block BP-742043302-172.31.0.2-1793536682410:blk_1073741825_1001
java.net.NoRouteToHostException: No route to host
...
2026-11-01 12:39:40,225 WARN hdfs.DFSClient: Failed to connect to /172.31.0.3:9866 for file /user/hadoop/input/moby-dick.txt for block BP-742043302-172.31.0.2-1793536682410:blk_1073741825_1001, add to deadNodes and continue.
...
2026-11-01 12:39:40,292 INFO hdfs.DFSClient: Successfully connected to /172.31.0.4:9866 for BP-742043302-172.31.0.2-1793536682410:blk_1073741825_1001
Call me Ishmael. Some years ago—never mind how long precisely—having
```

The warnings and Java stack traces are the client's retry, not a failure: the last line is the data. Whether
you see them depends on which replica the client tries first.

**Why nothing heals yet.** With 2 DataNodes, replication 2 and one node dead, there is nowhere to put a second
copy. HDFS waits for a new machine. Add the spare and poll `fsck`:

```
$ docker compose --profile spare up -d --wait datanode3
...
 Container hadoop-lab-datanode3-1 Healthy
$ while sleep 3; do docker compose exec -T namenode hdfs fsck /user/hadoop/input | grep -E 'Under-replicated|Average block'; done   # Ctrl-C to stop
```

My poll, local time:

```
14:29:28 |  Under-replicated blocks:	5 (100.0 %); Average block replication:	1.0;
14:29:32 |  Under-replicated blocks:	5 (100.0 %); Average block replication:	1.0;
14:29:36 |  Under-replicated blocks:	4 (80.0 %); Average block replication:	1.2;
14:29:40 |  Under-replicated blocks:	2 (40.0 %); Average block replication:	1.6;
14:29:44 |  Under-replicated blocks:	0 (0.0 %); Average block replication:	2.0;
```

Within about 15 s of datanode3 joining, the NameNode had every under-replicated block copied from datanode1
to datanode3:

```
$ docker compose exec -T namenode hdfs dfsadmin -report -live | grep -E '^Live|^Name:|^Hostname:|^DFS Used:'
DFS Used: 17084474 (16.29 MB)
Live datanodes (2):
Name: 172.31.0.5:9866 (hadoop-lab-datanode1-1.hadoop-lab_default)
Hostname: datanode1
DFS Used: 8542237 (8.15 MB)
Name: 172.31.0.6:9866 (hadoop-lab-datanode3-1.hadoop-lab_default)
Hostname: datanode3
DFS Used: 8542237 (8.15 MB)
```

Note `172.31.0.6`: Docker gave datanode3 the IP address datanode2 had. Go by the `Hostname:` lines, not the
IPs.

**Bonus: the dead node comes back**

```
$ docker compose start datanode2
```

40 seconds later:

```
$ docker compose exec -T namenode hdfs dfsadmin -report -live | grep -E '^Live|^Name:|^Hostname:|^DFS Used:'
DFS Used: 17172509 (16.38 MB)
Live datanodes (3):
Name: 172.31.0.5:9866 (hadoop-lab-datanode1-1.hadoop-lab_default)
Hostname: datanode1
DFS Used: 24576 (24 KB)
Name: 172.31.0.6:9866 (hadoop-lab-datanode3-1.hadoop-lab_default)
Hostname: datanode3
DFS Used: 8542237 (8.15 MB)
Name: 172.31.0.8:9866 (hadoop-lab-datanode2-1.hadoop-lab_default)
Hostname: datanode2
DFS Used: 8605696 (8.21 MB)
$ docker compose exec -T namenode hdfs fsck /user/hadoop/input | grep -E 'Under-replicated|Over-replicated|Average block replication'
 Over-replicated blocks:	0 (0.0 %)
 Under-replicated blocks:	0 (0.0 %)
 Average block replication:	2.0
```

datanode2 returned (with a new IP) carrying its old replicas, so for a moment some blocks had 3 copies. The
NameNode deleted the excess copies: replication is back to exactly 2.0, and in my run the copies removed
were datanode1's, whose `DFS Used` dropped to 24 KB. Which node loses its copies is the NameNode's choice
and may differ in your run.

**Check.** After the kill: `Dead datanodes (1)`, `Under-replicated blocks: 5`, `Missing blocks: 0`. After the
spare joins: `Under-replicated blocks: 0`, `Average block replication: 2.0`.

**Common mistakes**

- Expecting the dead node immediately: the NameNode needs about a minute. Until then `-report -dead` says
  `(0)`.
- Comparing IPs between before and after: Docker reuses them, use the host names.

---

## Step 9. Tear down

```
$ make down
docker compose --profile spare down -v --remove-orphans
 Container hadoop-lab-datanode3-1 Stopping
...
 Network hadoop-lab_default Removed
```

**What happens inside.** All containers, including the spare (`--profile spare`), are stopped and removed,
with their volumes (`-v`) and the network. HDFS lives inside the containers, so this erases it. The image
and `wordcount-java/target/wordcount.jar` stay. The next `make up` takes about 20 s and starts with an empty,
freshly formatted HDFS: run `make put-data` again.

**Check.** `docker ps` lists no `hadoop-lab-*` container.

`docker image rm bigdata-lab/hadoop:3.4.1` frees the 1.1 GB image when you no longer need the cluster.
