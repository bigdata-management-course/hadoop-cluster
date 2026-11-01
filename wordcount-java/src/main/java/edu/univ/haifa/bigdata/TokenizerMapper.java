package edu.univ.haifa.bigdata;

import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;

import java.io.IOException;
import java.util.Locale;
import java.util.regex.Pattern;

/** Emits (word, 1) for every run of letters a-z, lowercased. Must match wordcount-python/mapper.py. */
public class TokenizerMapper extends Mapper<LongWritable, Text, Text, IntWritable> {

    private static final Pattern NON_LETTERS = Pattern.compile("[^a-z]+");
    private static final IntWritable ONE = new IntWritable(1);
    // Reused across calls: map() runs once per line, allocating per word adds GC pressure.
    private final Text word = new Text();

    @Override
    protected void map(LongWritable offset, Text line, Context context) throws IOException, InterruptedException {
        for (String token : NON_LETTERS.split(line.toString().toLowerCase(Locale.ROOT))) {
            if (!token.isEmpty()) {
                word.set(token);
                context.write(word, ONE);
            }
        }
    }
}
