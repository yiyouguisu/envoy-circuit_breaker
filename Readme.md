## 一次发送10个并发请求, 结果部分通过

```shell
siege -c 10 -r 1 -v http://localhost:8081/service
** SIEGE 4.0.4
** Preparing 10 concurrent users for battle.
The server is now under siege...
HTTP/1.1 503     0.03 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.05 secs:      57 bytes ==> GET  /service
HTTP/1.1 200     0.06 secs:      31 bytes ==> GET  /service
HTTP/1.1 503     0.06 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.06 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.06 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.06 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.06 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.06 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.06 secs:      57 bytes ==> GET  /service

Transactions:		           1 hits
Availability:		       10.00 %
Elapsed time:		        0.07 secs
Data transferred:	        0.00 MB
Response time:		        0.56 secs
Transaction rate:	       14.29 trans/sec
Throughput:		        0.01 MB/sec
Concurrency:		        8.00
Successful transactions:           1
Failed transactions:	           9
Longest transaction:	        0.06
Shortest transaction:	        0.03

```

## 返回报文里的header域里包含 x-envoy-overloaded 

```shell
front-envoy_1  | ':status', '503'
front-envoy_1  | 'content-length', '57'
front-envoy_1  | 'content-type', 'text/plain'
front-envoy_1  | 'x-envoy-overloaded', 'true'
front-envoy_1  | 'date', 'Mon, 02 Sep 2019 05:27:19 GMT'
front-envoy_1  | 'server', 'circuit_breaker_test'
front-envoy_1  | 'connection', 'close'

```

## 修改运行时配置

```shell
curl --request POST \
  --url 'http://localhost:9901/runtime_modify?circuit_breakers.service1.default.max_connections=1024&circuit_breakers.service1.default.max_pending_requests=1024&circuit_breakers.service1.default.max_requests=10&circuit_breakers.service1.default.max_retries=3'

```


## 一次发送10个并发请求, 结果全部通过

```shell
siege -c 10 -r 1 -v http://localhost:8081/service
** SIEGE 4.0.4
** Preparing 10 concurrent users for battle.
The server is now under siege...
HTTP/1.1 200     0.05 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.07 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.08 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.09 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.10 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.12 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.13 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.16 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.16 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.18 secs:      31 bytes ==> GET  /service

Transactions:		          10 hits
Availability:		      100.00 %
Elapsed time:		        0.18 secs
Data transferred:	        0.00 MB
Response time:		        0.11 secs
Transaction rate:	       55.56 trans/sec
Throughput:		        0.00 MB/sec
Concurrency:		        6.33
Successful transactions:          10
Failed transactions:	           0
Longest transaction:	        0.18
Shortest transaction:	        0.05

```


## 一次发送12个并发请求, 结果部分通过

```shell
siege -c 12 -r 1 -v http://localhost:8081/service
** SIEGE 4.0.4
** Preparing 12 concurrent users for battle.
The server is now under siege...
HTTP/1.1 503     0.05 secs:      57 bytes ==> GET  /service
HTTP/1.1 503     0.05 secs:      57 bytes ==> GET  /service
HTTP/1.1 200     0.07 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.10 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.10 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.12 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.13 secs:      31 bytes ==> GET  /service
HTTP/1.1 504     0.14 secs:      24 bytes ==> GET  /service
HTTP/1.1 504     0.15 secs:      24 bytes ==> GET  /service
HTTP/1.1 200     0.17 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.18 secs:      31 bytes ==> GET  /service
HTTP/1.1 200     0.19 secs:      31 bytes ==> GET  /service

Transactions:		           8 hits
Availability:		       66.67 %
Elapsed time:		        0.19 secs
Data transferred:	        0.00 MB
Response time:		        0.18 secs
Transaction rate:	       42.11 trans/sec
Throughput:		        0.00 MB/sec
Concurrency:		        7.63
Successful transactions:           8
Failed transactions:	           4
Longest transaction:	        0.19
Shortest transaction:	        0.05

```