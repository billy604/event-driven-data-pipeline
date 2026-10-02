CREATE EXTERNAL TABLE orders (
  order_id string, customer_id string, product string,
  quantity int, unit_price double, total double
)
PARTITIONED BY (order_date string)
STORED AS PARQUET
LOCATION 's3://YOUR-BUCKET/processed/orders/'
TBLPROPERTIES (
  'projection.enabled'='true',
  'projection.order_date.type'='date',
  'projection.order_date.format'='yyyy-MM-dd',
  'projection.order_date.range'='2025-01-01,NOW',
  'storage.location.template'='s3://YOUR-BUCKET/processed/orders/order_date=${order_date}/'
);