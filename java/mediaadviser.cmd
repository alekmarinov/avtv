@echo off
java -cp lib/mahout-core-0.8.jar;lib/mahout-core-0.8-job.jar;lib/mahout-integration-0.8.jar;lib/mahout-math-0.8.jar;lib/commons-pool2-2.0.jar;lib/jedis-2.4.2.jar;bin intelibo.avtv.recommender.MediaAdviser localhost 6379
