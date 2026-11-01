package edu.univ.haifa.bigdata;

import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

import java.io.IOException;

/** Sums the counts for a word. Used both as the reducer and as the combiner. */
public class IntSumReducer extends Reducer<Text, IntWritable, Text, IntWritable> {

    private final IntWritable result = new IntWritable();

    @Override
    protected void reduce(Text word, Iterable<IntWritable> counts, Context context) throws IOException, InterruptedException {
        int sum = 0;
        for (IntWritable c : counts) {
            sum += c.get();
        }
        result.set(sum);
        context.write(word, result);
    }
}
