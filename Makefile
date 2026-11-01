# Run from this directory. Inside the namenode container this directory is mounted at /lab.
SHELL       := /bin/bash
.SHELLFLAGS := -eo pipefail -c

COMPOSE   := docker compose
NN        := $(COMPOSE) exec -T namenode
JAR       := /lab/wordcount-java/target/wordcount.jar
STREAMING := /opt/hadoop/share/hadoop/tools/lib/hadoop-streaming-3.4.1.jar
REDUCES   := 2
TOP10     := sort -t "$$(printf '\t')" -k2,2nr | head -10

.PHONY: up put-data jar java python compare combiner-demo down

up:
	$(COMPOSE) up -d --build --wait
	$(COMPOSE) ps

put-data:
	$(NN) hdfs dfs -mkdir -p input
	$(NN) sh -c 'hdfs dfs -put -f /lab/data/*.txt input/'
	$(NN) hdfs dfs -ls input

# Uses local Maven if present, otherwise a throwaway Maven container.
jar:
	@if command -v mvn >/dev/null; then \
	  mvn -q -f wordcount-java/pom.xml package; \
	else \
	  mkdir -p "$(HOME)/.m2"; \
	  docker run --rm --user "$$(id -u):$$(id -g)" -e MAVEN_CONFIG=/var/maven/.m2 \
	    -v "$(HOME)/.m2:/var/maven/.m2" -v "$(CURDIR)/wordcount-java:/src" -w /src \
	    maven:3.9.9-eclipse-temurin-11 mvn -q -Duser.home=/var/maven package; \
	fi

java: jar
	$(NN) hdfs dfs -rm -r -f -skipTrash out-java
	$(NN) hadoop jar $(JAR) -D mapreduce.job.reduces=$(REDUCES) input out-java
	@echo "--- top 10 words (Java) ---"
	@$(NN) hdfs dfs -cat 'out-java/part-r-*' | $(TOP10)

python:
	$(NN) hdfs dfs -rm -r -f -skipTrash out-python
	$(NN) mapred streaming -D mapreduce.job.reduces=$(REDUCES) \
	  -files /lab/wordcount-python/mapper.py,/lab/wordcount-python/reducer.py \
	  -mapper "python3 mapper.py" -combiner "python3 reducer.py" -reducer "python3 reducer.py" \
	  -input input -output out-python
	@echo "--- top 10 words (Python) ---"
	@$(NN) hdfs dfs -cat 'out-python/part-*' | $(TOP10)

compare:
	diff <($(NN) hdfs dfs -cat 'out-java/part-*' | LC_ALL=C sort) \
	     <($(NN) hdfs dfs -cat 'out-python/part-*' | LC_ALL=C sort)
	@echo "OK: Java and Python outputs are identical"

combiner-demo: jar
	@for c in true false; do \
	  echo "running wordcount with combiner=$$c ..." >&2; \
	  $(NN) hdfs dfs -rm -r -f -skipTrash out-combiner-$$c >/dev/null; \
	  $(NN) hadoop jar $(JAR) -D wordcount.combiner=$$c -D mapreduce.job.reduces=$(REDUCES) input out-combiner-$$c 2>&1 \
	    | sed -n -E "s/^[[:space:]]*(Map output records|Combine input records|Combine output records|Reduce input records|Reduce shuffle bytes)=([0-9]+).*/$$c	\1	\2/p"; \
	done | awk -F'\t' '!($$2 in v) {order[++n] = $$2} {v[$$2]; val[$$2, $$1] = $$3} \
	  END {printf "%-24s %15s %15s\n", "counter", "with combiner", "without"; \
	       for (i = 1; i <= n; i++) printf "%-24s %15s %15s\n", order[i], val[order[i], "true"], val[order[i], "false"]}'

down:
	$(COMPOSE) --profile spare down -v --remove-orphans
