package edu.univ.haifa.bigdata;

import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Partitioner;

/**
 * Range partitioner: splits a-z into N contiguous letter ranges, one per reducer.
 * With 2 reducers, part-r-00000 holds a..m and part-r-00001 holds n..z.
 */
public class AlphabetPartitioner extends Partitioner<Text, IntWritable> {

    @Override
    public int getPartition(Text word, IntWritable count, int numReducers) {
        int letter = Math.max(0, Math.min(25, word.charAt(0) - 'a'));
        return letter * numReducers / 26;
    }
}
