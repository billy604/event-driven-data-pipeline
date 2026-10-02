SELECT order_date, SUM(total) AS revenue, COUNT(*) AS orders
FROM orders
WHERE order_date BETWEEN '2025-06-01' AND '2025-06-07'
GROUP BY order_date
ORDER BY order_date;