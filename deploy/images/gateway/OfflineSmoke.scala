import java.io.PrintWriter
import java.time.ZoneId
import org.apache.hadoop.fs.Path
import org.apache.spark.SparkEnv
import org.apache.spark.sql.SparkSession
import scala.io.Source

object OfflineSmoke {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder().enableHiveSupport().getOrCreate()
    try {
      val sc = spark.sparkContext
      // 在任务所在 JVM 内读取时区。Read the zone inside each participating executor JVM.
      val executors = sc.parallelize(1 to 8, 8).mapPartitions { _ =>
        Iterator(SparkEnv.get.executorId -> ZoneId.systemDefault().getId)
      }.distinct().collect()
      val session = spark.sql("SELECT current_timezone()").head().getString(0)
      val driver = ZoneId.systemDefault().getId
      val zones = Seq(s"driver=$driver", s"session=$session") ++
        executors.map { case (id, zone) => s"executor[$id]=$zone" }
      val evidence = zones.mkString(" ")
      println(evidence)
      require(driver == "Asia/Shanghai" && session == driver &&
        executors.nonEmpty && executors.forall(_._2 == driver), evidence)
      val sql = Source.fromInputStream(getClass.getResourceAsStream("/smoke.sql"), "UTF-8")
      try sql.mkString.split(";").map(_.trim).filter(_.nonEmpty).foreach(s => spark.sql(s).collect())
      finally sql.close()
      // 用应用 ID 隔离证据，使网关能读取远程 driver 的结果。Publish evidence by application ID.
      val path = new Path("/tmp/dp_smoke/" + sc.applicationId + ".txt")
      val out = new PrintWriter(path.getFileSystem(sc.hadoopConfiguration).create(path), true)
      try out.println(evidence) finally out.close()
    } finally spark.stop()
  }
}
