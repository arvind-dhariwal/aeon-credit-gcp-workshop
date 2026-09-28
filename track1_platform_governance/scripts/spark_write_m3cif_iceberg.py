#!/usr/bin/env python3
"""Reads m3CIF.csv.gz (100,000 Customer Master rows) and writes directly into the
BigLake Apache Iceberg REST Catalog (`acsm_gcp_lakehouse_catalog.acsm_gcp_bronze.m3CIF`)
using PySpark + org.apache.iceberg.gcp.auth.GoogleAuthManager with vended credentials.
"""

import argparse
import os
import shutil
import subprocess
import urllib.request


def main():
    parser = argparse.ArgumentParser(
        description="Write m3CIF.csv.gz into BigLake Apache Iceberg REST Catalog using PySpark + GoogleAuthManager."
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("PROJECT_ID") or os.environ.get("GOOGLE_CLOUD_PROJECT", ""),
        help="Google Cloud Project ID",
    )
    parser.add_argument(
        "--location",
        default=os.environ.get("LOCATION", "asia-southeast1"),
        help="GCP Region (default: asia-southeast1)",
    )
    parser.add_argument(
        "--catalog",
        default="acsm_gcp_lakehouse_catalog",
        help="BigLake Iceberg REST Catalog name (default: acsm_gcp_lakehouse_catalog)",
    )
    parser.add_argument(
        "--namespace",
        default="acsm_gcp_bronze",
        help="BigLake Iceberg namespace (default: acsm_gcp_bronze)",
    )
    parser.add_argument(
        "--table",
        default="m3CIF",
        help="Target Iceberg table name (default: m3CIF)",
    )
    parser.add_argument(
        "--csv-path",
        default="aeon-credit-gcp-workshop/data/full_compressed/m3CIF.csv.gz",
        help="Path to m3CIF.csv.gz source extract",
    )
    args = parser.parse_args()

    project_id = args.project
    if not project_id:
        project_id = subprocess.check_output(
            ["gcloud", "config", "get-value", "project"], text=True
        ).strip()

    lakehouse_bucket = f"acsm-lakehouse-iceberg-{project_id}"
    lakehouse_catalog = args.catalog
    lakehouse_namespace = args.namespace
    lakehouse_table = args.table
    catalog_warehouse = f"bl://projects/{project_id}/catalogs/{lakehouse_catalog}"

    # 1. Ensure local CSV.GZ file is present
    csv_path = args.csv_path
    if not os.path.exists(csv_path):
        fallback_local = os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
            "data",
            "full_compressed",
            "m3CIF.csv.gz",
        )
        if os.path.exists(fallback_local):
            csv_path = fallback_local
        else:
            subprocess.run(
                [
                    "gcloud",
                    "storage",
                    "cp",
                    f"gs://acsm-workshop-landing-{project_id}/full_compressed/m3CIF.csv.gz",
                    "/tmp/m3CIF.csv.gz",
                ],
                check=True,
            )
            csv_path = "/tmp/m3CIF.csv.gz"

    # 2. Ensure Java 17/21 & clean SPARK_HOME so PySpark 4.0 / 3.5 Java Gateway starts cleanly
    if not shutil.which("java"):
        print("☕ Installing OpenJDK 17 for local PySpark runtime...")
        subprocess.run(["apt-get", "update", "-qq"], check=True)
        subprocess.run(["apt-get", "install", "-y", "-qq", "openjdk-17-jre-headless"], check=True)

    for jvm_candidate in [
        "/usr/lib/jvm/java-17-openjdk-amd64",
        "/usr/lib/jvm/java-21-openjdk-amd64",
    ]:
        if os.path.exists(jvm_candidate):
            os.environ["JAVA_HOME"] = jvm_candidate
            break
    os.environ.pop("SPARK_HOME", None)

    # Propagate Colab ADC file to Java child process if running in standard Google Colab
    if "GOOGLE_APPLICATION_CREDENTIALS" not in os.environ and os.path.exists(
        "/content/.config/application_default_credentials.json"
    ):
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = (
            "/content/.config/application_default_credentials.json"
        )

    try:
        import pyspark
    except ImportError:
        subprocess.run(["pip", "install", "-q", "pyspark"], check=True)
        import pyspark

    from pyspark.sql import SparkSession

    # 3. Download self-contained Apache Iceberg 1.10.1 Runtime & GCP Bundle JARs (includes GoogleAuthManager)
    #    Note: Spark 4.0 uses Scala 2.13 (`4.0_2.13`), while Spark 3.5 uses Scala 2.12 (`3.5_2.12`).
    spark_minor = ".".join(pyspark.__version__.split(".")[:2])
    scala_suffix = "2.13" if spark_minor.startswith("4.") else "2.12"
    iceberg_ver = "1.10.1"
    jar_dir = "/tmp/iceberg_jars"
    os.makedirs(jar_dir, exist_ok=True)

    runtime_jar_name = f"iceberg-spark-runtime-{spark_minor}_{scala_suffix}-{iceberg_ver}.jar"
    gcp_bundle_name = f"iceberg-gcp-bundle-{iceberg_ver}.jar"
    runtime_jar_path = os.path.join(jar_dir, runtime_jar_name)
    gcp_bundle_path = os.path.join(jar_dir, gcp_bundle_name)

    maven_mirror = "https://storage-download.googleapis.com/maven-central/maven2/org/apache/iceberg"
    for jar_name, artifact_id, dest_path in [
        (runtime_jar_name, f"iceberg-spark-runtime-{spark_minor}_{scala_suffix}", runtime_jar_path),
        (gcp_bundle_name, "iceberg-gcp-bundle", gcp_bundle_path),
    ]:
        if not os.path.exists(dest_path):
            url = f"{maven_mirror}/{artifact_id}/{iceberg_ver}/{jar_name}"
            print(f"⬇️ Downloading {jar_name}...")
            urllib.request.urlretrieve(url, dest_path)

    # 4. Initialize SparkSession with GoogleAuthManager & BigLake Iceberg REST Catalog
    print(
        f"🚀 Starting PySpark ({pyspark.__version__}, Scala {scala_suffix}) with GoogleAuthManager "
        f"connected to `{lakehouse_catalog}` (`{catalog_warehouse}`)..."
    )
    spark = (
        SparkSession.builder.appName("ACSM_PySpark_BigLake_Iceberg_Ingestion")
        .master("local[*]")
        .config("spark.driver.memory", "4g")
        .config("spark.jars", f"{runtime_jar_path},{gcp_bundle_path}")
        .config(
            "spark.sql.extensions",
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        )
        .config(f"spark.sql.catalog.{lakehouse_catalog}", "org.apache.iceberg.spark.SparkCatalog")
        .config(f"spark.sql.catalog.{lakehouse_catalog}.type", "rest")
        .config(
            f"spark.sql.catalog.{lakehouse_catalog}.uri",
            "https://biglake.googleapis.com/iceberg/v1/restcatalog",
        )
        .config(f"spark.sql.catalog.{lakehouse_catalog}.warehouse", catalog_warehouse)
        .config(
            f"spark.sql.catalog.{lakehouse_catalog}.header.x-goog-user-project",
            project_id,
        )
        .config(
            f"spark.sql.catalog.{lakehouse_catalog}.header.X-Iceberg-Access-Delegation",
            "vended-credentials",
        )
        .config(
            f"spark.sql.catalog.{lakehouse_catalog}.rest.auth.type",
            "org.apache.iceberg.gcp.auth.GoogleAuthManager",
        )
        .config(
            f"spark.sql.catalog.{lakehouse_catalog}.io-impl",
            "org.apache.iceberg.gcp.gcs.GCSFileIO",
        )
        .getOrCreate()
    )

    # 5. Read m3CIF.csv.gz (100,000 rows) in Spark & write directly into the Lakehouse Iceberg table
    print(f"📖 Reading `{csv_path}` (100,000 Customer Master rows) into Spark DataFrame...")
    df_m3cif = (
        spark.read.option("header", "true").option("inferSchema", "true").csv(csv_path)
    )

    full_iceberg_table = f"`{lakehouse_catalog}`.`{lakehouse_namespace}`.`{lakehouse_table}`"
    print(
        f"🧊 Writing 100,000 rows via PySpark directly into Iceberg table {full_iceberg_table} "
        f"on gs://{lakehouse_bucket}..."
    )
    spark.sql(f"DROP TABLE IF EXISTS {full_iceberg_table}")
    (
        df_m3cif.writeTo(f"{lakehouse_catalog}.{lakehouse_namespace}.{lakehouse_table}")
        .tableProperty("write.format.default", "parquet")
        .tableProperty("gcp.biglake.table-management", "disabled")
        .createOrReplace()
    )

    spark_count = spark.sql(f"SELECT COUNT(*) AS cnt FROM {full_iceberg_table}").collect()[0]["cnt"]
    print(
        f"✅ PySpark successfully wrote {spark_count:,} rows into "
        f"`{lakehouse_catalog}.{lakehouse_namespace}.{lakehouse_table}`!"
    )
    spark.stop()


if __name__ == "__main__":
    main()
