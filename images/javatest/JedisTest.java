package cn.test;

import com.xiaoleilu.hutool.util.RandomUtil;
import redis.clients.jedis.HostAndPort;
import redis.clients.jedis.JedisCluster;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * @author caiqyxyx
 * @date 2017/12/23
 */
public class JedisTest {
    public static void main(String[] args) {
        Set<HostAndPort> jedisClusterNodes = new HashSet<HostAndPort>();

        jedisClusterNodes.add(new HostAndPort("sf-redis-cluster-0.svc-redis-cluster", 6379));
        jedisClusterNodes.add(new HostAndPort("sf-redis-cluster-1.svc-redis-cluster", 6379));
        jedisClusterNodes.add(new HostAndPort("sf-redis-cluster-2.svc-redis-cluster", 6379));
        jedisClusterNodes.add(new HostAndPort("sf-redis-cluster-3.svc-redis-cluster", 6379));
        jedisClusterNodes.add(new HostAndPort("sf-redis-cluster-4.svc-redis-cluster", 6379));
        jedisClusterNodes.add(new HostAndPort("sf-redis-cluster-5.svc-redis-cluster", 6379));

        JedisCluster jc = new JedisCluster(jedisClusterNodes);

        ThreadPoolExecutor t =  new ThreadPoolExecutor(50,50,10, TimeUnit.SECONDS, new LinkedBlockingQueue<Runnable>());
        Runnable runnable = new RunRedis(jc);
        Long s = new java.util.Date().getTime();

        for(int i = 0 ;i < 50 ;i++) {
            t.execute(runnable);
        }
        t.shutdown();
        try {
            boolean loop = true;
            do {    //等待所有任务完成
                loop = !t.isTerminated();  //阻塞，直到线程池里所有任务结束
                Thread.sleep(100);
            } while(loop);
        } catch (Exception e) {
            e.printStackTrace();
        }
        Long p =  new java.util.Date().getTime() - s ;
        System.out.println(p + "ms");
    }


    public static class RunRedis implements  Runnable{
        JedisCluster jc  = null;

        public RunRedis(JedisCluster jc) {
            this.jc = jc;
        }

        @Override
        public void run() {
            for (int i = 0; i < 2000; i++) {
                jc.set(RandomUtil.randomString(6), RandomUtil.randomString(6));
            }
        }
    }
}
