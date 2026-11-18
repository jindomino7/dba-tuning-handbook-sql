/*  6. 인덱스의 기본 원리와 활용 방법 : t_0410 실습 데이터 생성 (MySQL 8.0+) */
/*
MySQL을 기본 설정으로 쓰면 버퍼 풀이 128MB뿐이라 훨씬 느려질 수 있습니다. 
그럴 때는 SET GLOBAL innodb_buffer_pool_size = 2147483648;로 2GB 정도    
늘려 주세요. 디스크는 3~4GB 정도 필요합니다.       
vCPU 2 RAM 4 GB 에서 진행하였습니다.
*/

-- DATABASE 
CREATE DATABASE IF NOT EXISTS handbook;
USE handbook;

-- 임시 테이블 
DROP TABLE IF EXISTS t_0410;
CREATE TABLE t_0410 (
  시퀀스 int,
  성별 varchar(1),
  기준일자 varchar(8),
  등록일시 date,
  PRIMARY KEY (시퀀스)
) DEFAULT CHARSET=utf8mb3;

-- 배치 적재용 번호 테이블 (1 ~ 100,000)
DROP TABLE IF EXISTS t_seq_tmp;
CREATE TABLE t_seq_tmp (n int PRIMARY KEY);
SET SESSION cte_max_recursion_depth = 100000;
INSERT INTO t_seq_tmp
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 100000
)
SELECT n FROM r;

-- 프로시져 생성  
DROP PROCEDURE IF EXISTS p_load_t_0410;
DELIMITER //
CREATE PROCEDURE p_load_t_0410(IN p_total int, IN p_batch int)
BEGIN
  DECLARE v_start int DEFAULT 0;
  WHILE v_start < p_total DO
    INSERT INTO t_0410 (시퀀스, 성별, 기준일자, 등록일시)
    SELECT v_start + s.n,
           SUBSTRING('FFFFFFFFFMMMMMMMMMEE', FLOOR(1 + RAND() * 20), 1),
           DATE_FORMAT(DATE_ADD('1970-01-01', INTERVAL FLOOR(RAND() * 20554) DAY), '%Y%m%d'),
           DATE_ADD('2020-01-01', INTERVAL FLOOR(RAND() * 2292) DAY)
      FROM t_seq_tmp s
     WHERE s.n <= p_batch
       AND v_start + s.n <= p_total;
    COMMIT;
    SET v_start = v_start + p_batch;
  END WHILE;
END//
DELIMITER ;

-- 건수 조정 필요시 : 맨 아래 CALL p_load_t_0410(전체건수, 배치건수) 의 첫 번째 값을 수정 

CALL p_load_t_0410(240000, 100000);

-- 인덱스는 적재 후 생성 (적재 속도 향상)
ALTER TABLE t_0410
  ADD KEY idx_t_0410_01 (성별),
  ADD KEY idx_t_0410_02 (기준일자),
  ADD KEY idx_t_0410_03 (등록일시);

-- 통계정보 갱신
ANALYZE TABLE t_0410;

-- 임시 테이블 프로시져 삭제 
DROP PROCEDURE p_load_t_0410;
DROP TABLE t_seq_tmp;

SELECT COUNT(*) AS cnt FROM t_0410;

/* 인덱스의 기본 원리와 활용 방법 : INDEX 비사용 / 사용 쿼리 실행계획 비교 */

-- (1) 컬럼에 함수 적용
EXPLAIN SELECT * FROM t_0410 WHERE SUBSTR(기준일자, 1, 4) = '1980';
EXPLAIN SELECT * FROM t_0410 WHERE 기준일자 LIKE '1980%';

-- (2) 컬럼에 연산 적용
EXPLAIN SELECT * FROM t_0410 WHERE 시퀀스 / 4 = 60000;
EXPLAIN SELECT * FROM t_0410 WHERE 시퀀스 = 60000 * 4;

-- (3) 날짜 컬럼에 함수 적용
EXPLAIN SELECT * FROM t_0410 WHERE DATE_FORMAT(등록일시, '%Y%m%d') = '20260224';
EXPLAIN SELECT * FROM t_0410 WHERE 등록일시 = DATE_FORMAT('20260224', '%Y-%m-%d');

-- (4) OR 조건
EXPLAIN SELECT COUNT(*) AS cnt
  FROM t_0410
 WHERE 성별 = 'F'
    OR 성별 = 'M';

EXPLAIN SELECT SUM(t.cnt) AS c_sum
  FROM (SELECT COUNT(*) AS cnt FROM t_0410 WHERE 성별 = 'F'
        UNION ALL
        SELECT COUNT(*) AS cnt FROM t_0410 WHERE 성별 = 'M') t;


/* 7. 실행계획에서 FULL TABLE SCAN 확인 : t_상품마스터, t_상품패키지 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @master_cnt, @package_cnt 수정 
-- (@package_cnt 는 3의 배수 권장, 패키지번호가 마스터 범위를 넘지 않도록 @master_cnt >= @package_cnt * 2 / 3 유지)

USE handbook;

SET @master_cnt  := 1000000;
SET @package_cnt := 1000000;
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_상품마스터;
CREATE TABLE t_상품마스터 (
  상품코드 varchar(25),
  상품명 varchar(80),
  상품레벨 int,
  변경일자 datetime,
  PRIMARY KEY (상품코드)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_상품패키지;
CREATE TABLE t_상품패키지 (
  패키지번호 varchar(25),
  시퀀스 int,
  상품속성 varchar(25),
  패키지수량 decimal(12,4),
  변경일자 datetime,
  PRIMARY KEY (패키지번호, 시퀀스)
) DEFAULT CHARSET=utf8mb3;

-- 상품코드: 300000000001 ~ (12자리)
INSERT INTO t_상품마스터 (상품코드, 상품명, 상품레벨, 변경일자)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @master_cnt
)
SELECT CONCAT('3', LPAD(n, 11, '0')),
       CONCAT('상품', LPAD(n, 7, '0')),
       FLOOR(1 + RAND() * 5),
       DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND() * 43200000) SECOND)
  FROM r;

-- 패키지 1개당 3건(시퀀스 1~3), 패키지번호는 마스터에 존재하는 상품코드
-- 상품속성은 패키지마다 고유한 값(400018000000 ~): 한 값당 3건, '400018146392' 존재
INSERT INTO t_상품패키지 (패키지번호, 시퀀스, 상품속성, 패키지수량, 변경일자)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @package_cnt
)
SELECT CONCAT('3', LPAD(((n - 1) DIV 3 + 1) * 2, 11, '0')),
       (n - 1) MOD 3 + 1,
       CAST(400018000000 + (n - 1) DIV 3 AS CHAR),
       ROUND(RAND() * 100, 4),
       DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND() * 43200000) SECOND)
  FROM r;

ANALYZE TABLE t_상품마스터, t_상품패키지;

SELECT COUNT(*) AS 마스터건수 FROM t_상품마스터;

SELECT COUNT(*) AS 패키지건수 FROM t_상품패키지;

SELECT 패키지번호, 시퀀스, 상품속성 FROM t_상품패키지 WHERE 상품속성 = '400018146392';


/* 7. 실행계획에서 FULL TABLE SCAN 확인 : 튜닝 전/후 실행계획 비교 */

-- 튜닝 전 상태로 되돌리기 (재실행용)
-- ALTER TABLE t_상품패키지 DROP KEY idx_t_상품패키지_01;

-- < 튜닝 전 실행계획 > rp 테이블 type = ALL (FULL TABLE SCAN)
EXPLAIN
SELECT 상품코드 AS item_no
  FROM t_상품마스터 AS im
 WHERE im.상품코드 IN (SELECT rp.패키지번호
                         FROM t_상품패키지 AS rp
                        WHERE rp.상품속성 = '400018146392');

-- 튜닝: 상품속성 인덱스 추가
ALTER TABLE t_상품패키지 ADD KEY idx_t_상품패키지_01 (상품속성);
ANALYZE TABLE t_상품패키지;

-- < 튜닝 후 실행계획 > rp 테이블 key = idx_t_상품패키지_01 (INDEX SCAN)
EXPLAIN
SELECT 상품코드 AS item_no
  FROM t_상품마스터 AS im
 WHERE im.상품코드 IN (SELECT rp.패키지번호
                         FROM t_상품패키지 AS rp
                        WHERE rp.상품속성 = '400018146392');


/* 8. 부적절한 인덱스 선택으로 인한 성능 저하 : t_결제정보 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @pay_cnt 수정 (@pay_cnt 를 늘리면 cte_max_recursion_depth 도 같이 늘려야 함)

USE handbook;

SET @pay_cnt := 1000000;

SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_결제정보;
CREATE TABLE t_결제정보 (
  결제번호 bigint,
  결제상태 varchar(5),
  결제완료일자 datetime,
  리턴메시지 varchar(30),
  등록일시 datetime,
  PRIMARY KEY (결제번호)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_결제정보 (결제번호, 결제상태, 결제완료일자, 리턴메시지, 등록일시)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @pay_cnt
)
SELECT 202000000000 + n,
       ELT(1 + FLOOR(RAND() * 20),
           'PAY02',
           'PAY01', 'PAY01', 'PAY01', 'PAY01', 'PAY01', 'PAY01', 'PAY01', 'PAY01',
           'PAY03', 'PAY03', 'PAY03', 'PAY03',
           'PAY04', 'PAY04', 'PAY04',
           'PAY05', 'PAY05', 'PAY05', 'PAY05'),
       DATE_ADD('2024-02-01', INTERVAL ((n * 7919) MOD 68256000) + 30 SECOND),
       CONCAT('MSG_', LPAD(1 + FLOOR(RAND() * 5), 2, '0')),
       DATE_ADD('2024-02-01', INTERVAL (n * 7919) MOD 68256000 SECOND)
  FROM r;

-- 인덱스는 적재 후 생성 (적재 속도 향상), 튜닝 전 인덱스 2개
ALTER TABLE t_결제정보
  ADD KEY idx_t_결제정보_01 (결제완료일자),
  ADD KEY idx_t_결제정보_02 (결제상태, 결제번호);

ANALYZE TABLE t_결제정보;

SELECT COUNT(*) AS 결제건수 FROM t_결제정보;

SELECT 결제상태, COUNT(*) AS cnt FROM t_결제정보 GROUP BY 결제상태 ORDER BY 결제상태;

SELECT COUNT(*) AS 조건건수
  FROM t_결제정보
 WHERE 등록일시 BETWEEN '2026-03-18 00:00:00' AND '2026-03-18 23:59:59';


/* 8. 부적절한 인덱스 선택으로 인한 성능 저하 : 튜닝 전/후 실행계획 비교 */

USE handbook;

-- 튜닝 전 상태로 되돌리기 (재실행용)
-- ALTER TABLE t_결제정보 DROP KEY idx_t_결제정보_03;

EXPLAIN
SELECT a.등록일, a.리턴메시지, a.건수
  FROM ( SELECT DATE_FORMAT(등록일시, '%Y-%m-%d') AS 등록일
              , 리턴메시지
              , COUNT(*) AS 건수
           FROM t_결제정보
          WHERE 등록일시 BETWEEN DATE_FORMAT('2026-03-18 00:00:00', '%Y-%m-%d %H:%i:%s')
                             AND DATE_FORMAT('2026-03-18 23:59:59', '%Y-%m-%d %H:%i:%s')
            AND 결제상태 = 'PAY02' /* 결제완료 */
          GROUP BY DATE_FORMAT(등록일시, '%Y-%m-%d'), 리턴메시지
         HAVING COUNT(*) > 5 ) a
 ORDER BY a.등록일 DESC, a.건수 DESC;

-- 튜닝: 분포도가 좋은 등록일시를 앞에 둔 복합 인덱스 추가
ALTER TABLE t_결제정보 ADD KEY idx_t_결제정보_03 (등록일시, 결제상태);
ANALYZE TABLE t_결제정보;

-- < 튜닝 후 실행계획 > t_결제정보 type = range, key = idx_t_결제정보_03
EXPLAIN
SELECT a.등록일, a.리턴메시지, a.건수
  FROM ( SELECT DATE_FORMAT(등록일시, '%Y-%m-%d') AS 등록일
              , 리턴메시지
              , COUNT(*) AS 건수
           FROM t_결제정보
          WHERE 등록일시 BETWEEN DATE_FORMAT('2026-03-18 00:00:00', '%Y-%m-%d %H:%i:%s')
                             AND DATE_FORMAT('2026-03-18 23:59:59', '%Y-%m-%d %H:%i:%s')
            AND 결제상태 = 'PAY02' /* 결제완료 */
          GROUP BY DATE_FORMAT(등록일시, '%Y-%m-%d'), 리턴메시지
         HAVING COUNT(*) > 5 ) a
 ORDER BY a.등록일 DESC, a.건수 DESC;


/* 9. 문자형 컬럼 인덱스 활용 사례(형 변환 주의) : t_상품마스터, t_상품패키지 실습 데이터 사용 (MySQL 8.0+) */

-- 7번에서 생성한 t_상품마스터, t_상품패키지 사용 (테이블을 다시 만들지 않습니다)

USE handbook;

-- 책 그림(901)은 상품속성 인덱스(idx_t_상품패키지_01)가 있는 상태입니다.
-- 7번 튜닝 후라면 이미 존재하므로 건너뛰고, 없으면 새로 생성합니다.
ALTER TABLE t_상품패키지 ADD KEY idx_t_상품패키지_01 (상품속성);
ANALYZE TABLE t_상품패키지;

SELECT COUNT(*) AS 패키지건수 FROM t_상품패키지;

SELECT 패키지번호, 시퀀스, 상품속성 FROM t_상품패키지 WHERE 상품속성 = '400018146392';


/* 9. 문자형 컬럼 인덱스 활용 사례(형 변환 주의) : 튜닝 전/후 실행계획 비교 */

USE handbook;

-- 이 사례는 인덱스를 추가하지 않고 쿼리의 조건값 타입만 바꾸므로 되돌릴 인덱스 작업은 없습니다.
-- (idx_t_상품패키지_01 이 없다면 위 섹션의 ADD KEY 를 먼저 실행)

-- < 튜닝 전 실행계획 > 조건값이 숫자(400018146392) : rp type = index (인덱스 전체 스캔), rows 가 전체 건수 수준
EXPLAIN
SELECT 상품코드 AS item_no
  FROM t_상품마스터 AS im
 WHERE im.상품코드 IN ( SELECT rp.패키지번호
                          FROM t_상품패키지 AS rp
                         WHERE rp.상품속성 = 400018146392 );

-- 튜닝: 조건값을 인덱스 컬럼 타입(문자)에 맞게 수정  400018146392 -> '400018146392'

-- < 튜닝 후 실행계획 > rp type = ref, key = idx_t_상품패키지_01, rows = 3
EXPLAIN
SELECT 상품코드 AS item_no
  FROM t_상품마스터 AS im
 WHERE im.상품코드 IN ( SELECT rp.패키지번호
                          FROM t_상품패키지 AS rp
                         WHERE rp.상품속성 = '400018146392' );


/* 10. 날짜형 컬럼 인덱스 활용 사례 : t_검색주문상품 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @order_cnt 수정 (@order_cnt 를 늘리면 cte_max_recursion_depth 도 같이 늘려야 함)

USE handbook;

SET @order_cnt := 1000000;

SET SESSION cte_max_recursion_depth = 1000000;

SET @span_days  := CEIL(@order_cnt / 3735);
SET @start_date := DATE_SUB(CURDATE(), INTERVAL @span_days DAY);

DROP TABLE IF EXISTS t_검색주문상품;
CREATE TABLE t_검색주문상품 (
  시퀀스 int,
  주문번호 bigint(25),
  고객번호 bigint(25),
  상품코드 varchar(30),
  주문일자 datetime,
  PRIMARY KEY (시퀀스)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_검색주문상품 (시퀀스, 주문번호, 고객번호, 상품코드, 주문일자)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @order_cnt
)
SELECT n,
       3000000000 + n,
       1 + FLOOR(RAND() * 200000),
       CONCAT('P', LPAD(1 + FLOOR(RAND() * 50000), 8, '0')),
       DATE_ADD(@start_date, INTERVAL (n * 7919) MOD (@span_days * 86400) SECOND)
  FROM r;

-- 인덱스는 적재 후 생성 (적재 속도 향상)
ALTER TABLE t_검색주문상품
  ADD KEY idx_t_검색주문상품_01 (고객번호, 상품코드),
  ADD KEY idx_t_검색주문상품_02 (주문일자);

ANALYZE TABLE t_검색주문상품;

SELECT COUNT(*) AS 주문건수 FROM t_검색주문상품;

SELECT COUNT(*) AS 삭제대상건수
  FROM t_검색주문상품
 WHERE 주문일자 >= DATE_ADD(CURDATE(), INTERVAL -91 DAY)
   AND 주문일자 <  DATE_ADD(CURDATE(), INTERVAL -90 DAY);


/* 10. 날짜형 컬럼 인덱스 활용 사례 : 튜닝 전/후 실행계획 비교 */

USE handbook;

-- < 튜닝 전 실행계획 > 주문일자 컬럼 변형 LEFT(주문일자, 10) : type = ALL (FULL TABLE SCAN)
EXPLAIN
DELETE FROM t_검색주문상품
 WHERE LEFT(주문일자, 10) = LEFT(NOW() - INTERVAL 91 DAY, 10);

-- < 튜닝 후 실행계획 > type = range, key = idx_t_검색주문상품_02
EXPLAIN
DELETE FROM t_검색주문상품
 WHERE 주문일자 >= DATE_ADD(CURDATE(), INTERVAL -91 DAY)
   AND 주문일자 <  DATE_ADD(CURDATE(), INTERVAL -90 DAY);

/* 11. 검색 범위 확대에 따른 인덱스와 FULL TABLE SCAN : t_검색주문상품 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @order_cnt 수정 (@order_cnt 를 늘리면 cte_max_recursion_depth 도 같이 늘려야 함)

USE handbook;

SET @order_cnt := 1000000;

SET SESSION cte_max_recursion_depth = 1000000;

SET @span_days  := 2097;
SET @start_date := '2021-01-01';

DROP TABLE IF EXISTS t_검색주문상품;
CREATE TABLE t_검색주문상품 (
  시퀀스 int,
  주문번호 bigint(25),
  고객번호 bigint(25),
  상품코드 varchar(30),
  주문일자 datetime,
  PRIMARY KEY (시퀀스)
) DEFAULT CHARSET=utf8mb3;

-- 주문번호: 3000000001 ~, 고객번호: 1 ~ 200,000 랜덤, 상품코드: P00000001 ~ P00050000 랜덤
INSERT INTO t_검색주문상품 (시퀀스, 주문번호, 고객번호, 상품코드, 주문일자)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @order_cnt
)
SELECT n,
       3000000000 + n,
       1 + FLOOR(RAND() * 200000),
       CONCAT('P', LPAD(1 + FLOOR(RAND() * 50000), 8, '0')),
       DATE_ADD(@start_date, INTERVAL (n * 7919) MOD (@span_days * 86400) SECOND)
  FROM r;

-- 인덱스는 적재 후 생성 (적재 속도 향상)
ALTER TABLE t_검색주문상품
  ADD KEY idx_t_검색주문상품_01 (고객번호, 상품코드),
  ADD KEY idx_t_검색주문상품_02 (주문일자);

ANALYZE TABLE t_검색주문상품;

SELECT COUNT(*) AS 주문건수 FROM t_검색주문상품;

/* 11. 검색 범위 확대에 따른 인덱스와 FULL TABLE SCAN : 실행계획 비교 */

USE handbook;

-- 이 사례는 인덱스 추가/삭제가 없습니다. 조회 범위가 달라질 때 옵티마이저의 선택이 바뀌는 것을 확인합니다.
--     인덱스/FULL TABLE SCAN 의 경계는 건수, 버퍼 풀, 통계에 따라 달라 실습 환경에서는 다르게 나올 수 있음
EXPLAIN
SELECT *
  FROM t_검색주문상품
 WHERE 주문일자 >= '2025-11-14'
   AND 주문일자 <  '2026-09-29'
UNION ALL
SELECT *
  FROM t_검색주문상품
 WHERE 주문일자 >= '2025-11-15'
   AND 주문일자 <  '2026-09-29';


/* 12. UNION ALL 활용 사례 : t_쿠폰관리, t_쿠폰정보 실습 데이터 생성 (MySQL 8.0+) */

USE handbook;

SET @mng_cnt  := 1000000;
SET @info_cnt := 1000000;
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_쿠폰관리;
CREATE TABLE t_쿠폰관리 (
  마일리지번호 bigint,
  발급시작일 date,
  발급종료일 date,
  쿠폰번호 varchar(20),
  등록일 datetime,
  PRIMARY KEY (마일리지번호),
  KEY idx_t_쿠폰관리_01 (쿠폰번호),
  KEY idx_t_쿠폰관리_02 (발급시작일, 발급종료일)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_쿠폰정보;
CREATE TABLE t_쿠폰정보 (
  쿠폰시퀀스 bigint,
  쿠폰번호 varchar(20),
  마일리지번호 bigint,
  쿠폰사용일 datetime,
  적립번호 bigint,
  PRIMARY KEY (쿠폰시퀀스),
  KEY idx_t_쿠폰정보_01 (쿠폰번호),
  KEY idx_t_쿠폰정보_02 (마일리지번호, 쿠폰사용일)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_쿠폰관리 (마일리지번호, 발급시작일, 발급종료일, 쿠폰번호, 등록일)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @mng_cnt
)
SELECT n,
       IF(n IN (500000, 700000), CURDATE(), DATE_ADD(CURDATE(), INTERVAL 1 + (n MOD 365) DAY)),
       IF(n IN (500000, 700000), CURDATE(), DATE_ADD(CURDATE(), INTERVAL 31 + (n MOD 365) DAY)),
       IF(n = 500000, '5FC0395606A5D720', UPPER(SUBSTR(MD5(CONCAT('m', n)), 1, 16))),
       DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND() * 43200000) SECOND)
  FROM r;

INSERT INTO t_쿠폰정보 (쿠폰시퀀스, 쿠폰번호, 마일리지번호, 쿠폰사용일, 적립번호)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @info_cnt
)
SELECT n,
       IF(n = 700000, '5FC0395606A5D720', UPPER(SUBSTR(MD5(CONCAT('i', n)), 1, 16))),
       n,
       DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND() * 43200000) SECOND),
       n
  FROM r;

ANALYZE TABLE t_쿠폰관리, t_쿠폰정보;

SELECT COUNT(*) AS 쿠폰관리건수 FROM t_쿠폰관리;

SELECT COUNT(*) AS 쿠폰정보건수 FROM t_쿠폰정보;

SELECT 마일리지번호, 발급시작일, 발급종료일, 쿠폰번호 FROM t_쿠폰관리 WHERE 쿠폰번호 = '5FC0395606A5D720';

SELECT 쿠폰시퀀스, 마일리지번호, 쿠폰번호 FROM t_쿠폰정보 WHERE 쿠폰번호 = '5FC0395606A5D720';


/* 12. UNION ALL 활용 사례 : 튜닝 전/후 실행계획 비교 */

-- < 튜닝 전 실행계획 > mcm 테이블 type = ALL (FULL TABLE SCAN)
-- OR 조건이 서로 다른 테이블(mcm.쿠폰번호 / mci.쿠폰번호)에 걸려 있어 인덱스를 사용하지 못함
EXPLAIN
SELECT MAX(mcm.마일리지번호) AS 마일리지번호
     , IFNULL(MAX(mci.쿠폰시퀀스), '') AS 쿠폰시퀀스
     , DATE_FORMAT(MAX(mcm.등록일), '%Y-%m-%d') AS 등록일
  FROM t_쿠폰관리 mcm
       LEFT JOIN t_쿠폰정보 mci ON mci.마일리지번호 = mcm.마일리지번호
 WHERE mcm.발급시작일 >= CURDATE()
   AND mcm.발급종료일 <= CURDATE()
   AND (mcm.쿠폰번호 = '5FC0395606A5D720'
        OR mci.쿠폰번호 = '5FC0395606A5D720');

-- 튜닝: OR 조건을 UNION ALL 로 분리 (각 쿼리의 쿠폰번호 컬럼에 인덱스 존재)
-- < 튜닝 후 실행계획 > 첫 번째 쿼리: mcm -> mci, 두 번째 쿼리: mci_2 -> mcm_2
EXPLAIN
SELECT MAX(t.마일리지번호) AS 마일리지번호
     , IFNULL(MAX(t.쿠폰시퀀스), '') AS 쿠폰시퀀스
     , DATE_FORMAT(MAX(t.등록일), '%Y-%m-%d') AS 등록일
  FROM (SELECT mcm.마일리지번호
             , mci.쿠폰시퀀스
             , mcm.등록일
          FROM t_쿠폰관리 mcm
               LEFT OUTER JOIN t_쿠폰정보 mci ON mci.마일리지번호 = mcm.마일리지번호
         WHERE mcm.발급시작일 >= CURDATE()
           AND mcm.발급종료일 <= CURDATE()
           AND mcm.쿠폰번호 = '5FC0395606A5D720'
        UNION ALL
        SELECT mcm_2.마일리지번호
             , mci_2.쿠폰시퀀스
             , mcm_2.등록일
          FROM t_쿠폰관리 mcm_2
               LEFT OUTER JOIN t_쿠폰정보 mci_2 ON mci_2.마일리지번호 = mcm_2.마일리지번호
         WHERE mcm_2.발급시작일 >= CURDATE()
           AND mcm_2.발급종료일 <= CURDATE()
           AND mci_2.쿠폰번호 = '5FC0395606A5D720') t;

/* 13. LEFT JOIN의 기본 개념 : t_고객정보, t_탈퇴정보 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @cust_cnt, @withdraw_cnt 수정

SET @cust_cnt     := 10000;
SET @withdraw_cnt := 500;
SET SESSION cte_max_recursion_depth = 10000;

-- 가정: 고객번호는 두 테이블의 조인 키(varchar), 가입일자 조건용 인덱스 1개
DROP TABLE IF EXISTS t_고객정보;
CREATE TABLE t_고객정보 (
  고객번호 varchar(20),
  고객명 varchar(50),
  가입일자 date,
  성별 varchar(1),
  PRIMARY KEY (고객번호),
  KEY idx_t_고객정보_01 (가입일자)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_탈퇴정보;
CREATE TABLE t_탈퇴정보 (
  고객번호 varchar(20),
  탈퇴일자 date,
  탈퇴코드 varchar(2),
  PRIMARY KEY (고객번호)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_고객정보 (고객번호, 고객명, 가입일자, 성별)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @cust_cnt
)
SELECT CONCAT('C', LPAD(n, 9, '0')),
       CONCAT('고객', LPAD(n, 7, '0')),
       DATE_ADD('2020-01-01', INTERVAL (n MOD 2300) DAY),
       IF(n MOD 2 = 0, 'F', 'M')
  FROM r;

INSERT INTO t_탈퇴정보 (고객번호, 탈퇴일자, 탈퇴코드)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @withdraw_cnt
),
x AS (
  SELECT n, (n - 1) * 20 + 1 + (n MOD 20) AS m FROM r
)
SELECT CONCAT('C', LPAD(m, 9, '0')),
       DATE_ADD(DATE_ADD('2020-01-01', INTERVAL (m MOD 2300) DAY), INTERVAL 1 + (n MOD 300) DAY),
       ELT(n MOD 3 + 1, 'A1', 'B2', 'C3')
  FROM x;

ANALYZE TABLE t_고객정보, t_탈퇴정보;

SELECT COUNT(*) AS 고객건수 FROM t_고객정보;

SELECT COUNT(*) AS 탈퇴건수 FROM t_탈퇴정보;

SELECT COUNT(*) AS 가입_2026년3월 FROM t_고객정보 WHERE 가입일자 >= '2026-03-01' AND 가입일자 < '2026-04-01';


-- 질문 1) 3월에 가입한 전체 고객명 추출, 탈퇴한 고객은 탈퇴일자 표시
EXPLAIN
SELECT A.고객명
     , B.탈퇴일자
  FROM t_고객정보 AS A
       LEFT JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01';

-- 질문 2) 질문 1 + 탈퇴코드 'A1' 인 탈퇴일자만 표시 -> 조건을 ON 절에 추가 (결과 건수는 질문 1과 동일)
EXPLAIN
SELECT A.고객명
     , B.탈퇴일자
  FROM t_고객정보 AS A
       LEFT JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
                                AND B.탈퇴코드 = 'A1'
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01';

-- 질문 3) 3월에 가입한 고객 중 탈퇴한 고객만 표시 -> INNER JOIN
EXPLAIN
SELECT A.고객명
     , B.탈퇴일자
  FROM t_고객정보 AS A
       INNER JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01';

-- 질문 4) 3월에 가입한 전체 고객명 추출, 탈퇴한 고객은 제외 -> LEFT JOIN + B.고객번호 IS NULL
EXPLAIN
SELECT A.고객명
  FROM t_고객정보 AS A
       LEFT JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01'
   AND B.고객번호 IS NULL;

-- 질문 4) 다른 방법 : NOT EXISTS
EXPLAIN
SELECT A.고객명
  FROM t_고객정보 AS A
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01'
   AND NOT EXISTS (SELECT 'X'
                     FROM t_탈퇴정보 AS B
                    WHERE B.고객번호 = A.고객번호);

-- 결과 건수 비교 (건수 비교용)
-- 질문 1 / 질문 2 : 3월 가입 전체 고객 수와 동일해야 함
SELECT COUNT(*) AS 질문1_건수
  FROM t_고객정보 AS A
       LEFT JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01';

SELECT COUNT(*) AS 질문2_건수
  FROM t_고객정보 AS A
       LEFT JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
                                AND B.탈퇴코드 = 'A1'
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01';

-- 잘못된 예 : 탈퇴코드 조건을 WHERE 절에 두면 LEFT JOIN 이 INNER JOIN 처럼 동작하여 건수가 줄어듦
SELECT COUNT(*) AS 잘못된_질문2_건수
  FROM t_고객정보 AS A
       LEFT JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01'
   AND B.탈퇴코드 = 'A1';

-- 질문 3 : 3월 가입 + 탈퇴한 고객만
SELECT COUNT(*) AS 질문3_건수
  FROM t_고객정보 AS A
       INNER JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01';

-- 질문 4 : 질문 1 - 질문 3 (LEFT JOIN IS NULL 방식과 NOT EXISTS 방식 건수 동일)
SELECT COUNT(*) AS 질문4_LEFTJOIN_건수
  FROM t_고객정보 AS A
       LEFT JOIN t_탈퇴정보 AS B ON B.고객번호 = A.고객번호
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01'
   AND B.고객번호 IS NULL;

SELECT COUNT(*) AS 질문4_NOTEXISTS_건수
  FROM t_고객정보 AS A
 WHERE A.가입일자 >= '2026-03-01'
   AND A.가입일자 <  '2026-04-01'
   AND NOT EXISTS (SELECT 'X'
                     FROM t_탈퇴정보 AS B
                    WHERE B.고객번호 = A.고객번호);


/* 14. LEFT JOIN 성능 개선 사례 : t_고객정보, t_로그인정보 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @cust_cnt, @login_cnt, @login_member_cnt, @login_hour_cnt 수정

USE handbook;

SET @cust_cnt         := 1000000;
SET @login_cnt        := 1000000;
SET @login_member_cnt := 12345;
SET @login_hour_cnt   := 122276;
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_고객정보;
CREATE TABLE t_고객정보 (
  고객번호 varchar(20),
  인증여부 varchar(1),
  PRIMARY KEY (고객번호)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_로그인정보;
CREATE TABLE t_로그인정보 (
  시퀀스 bigint,
  회원번호 bigint,
  등록일자 datetime,
  PRIMARY KEY (시퀀스),
  KEY idx_t_로그인정보_01 (회원번호),
  KEY idx_t_로그인정보_02 (등록일자, 회원번호)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_고객정보 (고객번호, 인증여부)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @cust_cnt
)
SELECT CAST(100000000000 + n AS CHAR),
       IF(n MOD 10 = 0, 'Y', 'N')
  FROM r;

INSERT INTO t_로그인정보 (시퀀스, 회원번호, 등록일자)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @login_cnt
)
SELECT n,
       100000000000 + ((n - 1) MOD @login_member_cnt) * 81 + 1,
       IF(n <= @login_hour_cnt,
          DATE_ADD('2026-04-15 00:00:00', INTERVAL (n MOD 3600) SECOND),
          DATE_ADD('2026-01-01 00:00:00', INTERVAL FLOOR(RAND() * 8640000) SECOND))
  FROM r;

ANALYZE TABLE t_고객정보, t_로그인정보;

SELECT COUNT(*) AS 고객건수 FROM t_고객정보;

SELECT COUNT(*) AS 로그인건수 FROM t_로그인정보;

SELECT COUNT(*) AS 조회구간_로그인건수 FROM t_로그인정보
 WHERE 등록일자 >= '2026-04-15 00:00:00' AND 등록일자 < '2026-04-15 01:00:00';


/* 14. LEFT JOIN 성능 개선 사례 : 튜닝 전/후 실행계획 비교 */

EXPLAIN
SELECT A.고객번호
     , B.등록일자
  FROM t_고객정보 AS A
       LEFT JOIN t_로그인정보 AS B ON B.회원번호 = A.고객번호
 WHERE A.인증여부 = 'Y'
   AND B.등록일자 >= '2026-04-15 00:00:00'
   AND B.등록일자 <  '2026-04-15 01:00:00';

-- 튜닝: ON B.회원번호 = A.고객번호  ->  ON CONCAT(B.회원번호, '') = A.고객번호
--       (B 컬럼을 문자로 변환해 A.고객번호 타입에 맞추고, t_로그인정보를 선행 테이블로 유도)

-- < 튜닝 후 실행계획 > t_로그인정보 type = range (idx_t_로그인정보_02), t_고객정보 type = eq_ref (PRIMARY)

EXPLAIN
SELECT A.고객번호
     , B.등록일자
  FROM t_고객정보 AS A
       LEFT JOIN t_로그인정보 AS B ON CONCAT(B.회원번호, '') = A.고객번호
 WHERE A.인증여부 = 'Y'
   AND B.등록일자 >= '2026-04-15 00:00:00'
   AND B.등록일자 <  '2026-04-15 01:00:00';


/* 15. 조인 조건의 함수 적용에 따른 실행계획 변경 : t_소장현황, t_도서, t_분관도서대출, t_도서서비스, t_분관 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @hold_cnt, @book_cnt 수정

USE handbook;

SET @hold_cnt := 1000000;
SET @book_cnt := 500000;
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_소장현황;
CREATE TABLE t_소장현황 (
  분관번호 int,
  도서번호 varchar(25),
  갱신일시 datetime,
  PRIMARY KEY (분관번호, 도서번호),
  KEY idx_t_소장현황_01 (갱신일시)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_도서;
CREATE TABLE t_도서 (
  도서번호 varchar(25),
  도서상태 char(1),
  자료유형 char(2),
  열람공개여부 char(1),
  등록일시 datetime,
  PRIMARY KEY (도서번호),
  KEY idx_t_도서_01 (자료유형, 등록일시),
  KEY idx_t_도서_02 (도서상태, 열람공개여부)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_분관도서대출;
CREATE TABLE t_분관도서대출 (
  도서번호 varchar(25),
  분관번호 int,
  대출정지여부 char(1),
  정지기간제한여부 char(1),
  정지시작일시 datetime,
  정지종료일시 datetime,
  PRIMARY KEY (도서번호, 분관번호),
  KEY idx_t_분관도서대출_01 (분관번호),
  KEY idx_t_분관도서대출_02 (정지시작일시, 도서번호),
  KEY idx_t_분관도서대출_03 (정지종료일시, 도서번호),
  KEY idx_t_분관도서대출_04 (대출정지여부, 정지기간제한여부)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_도서서비스;
CREATE TABLE t_도서서비스 (
  도서번호 varchar(25),
  분관유형 varchar(7),
  서비스기간제한여부 char(1),
  서비스시작일시 datetime,
  서비스종료일시 datetime,
  예약가능여부 char(1),
  PRIMARY KEY (도서번호, 분관유형),
  KEY idx_t_도서서비스_01 (서비스기간제한여부, 서비스종료일시),
  KEY idx_t_도서서비스_02 (분관유형, 예약가능여부, 서비스기간제한여부, 서비스종료일시)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_분관;
CREATE TABLE t_분관 (
  분관번호 int,
  분관유형 varchar(7),
  운영여부 char(1),
  예약가능여부 char(1),
  PRIMARY KEY (분관번호),
  KEY idx_t_분관_01 (분관유형, 운영여부, 예약가능여부)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_분관 (분관번호, 분관유형, 운영여부, 예약가능여부)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 404
)
SELECT n,
       IF(n <= 250, 'HYPER', 'MINI'),
       IF(n BETWEEN 119 AND 150, 'N', 'Y'),
       IF(n BETWEEN 151 AND 250, 'N', 'Y')
  FROM r;

INSERT INTO t_도서 (도서번호, 도서상태, 자료유형, 열람공개여부, 등록일시)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @book_cnt
)
SELECT CONCAT('B', LPAD(n, 10, '0')),
       IF((n DIV 5) MOD 2 = 0, 'A', 'D'),
       ELT(n MOD 5 + 1, 'TD', 'BK', 'MG', 'AV', 'ET'),
       IF((n DIV 10) MOD 2 = 0, 'Y', 'N'),
       DATE_ADD('2020-01-01', INTERVAL FLOOR(RAND() * 190000000) SECOND)
  FROM r;

INSERT INTO t_도서서비스 (도서번호, 분관유형, 서비스기간제한여부, 서비스시작일시, 서비스종료일시, 예약가능여부)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @book_cnt * 2
),
x AS (
  SELECT n, (n - 1) DIV 2 + 1 AS k FROM r
)
SELECT CONCAT('B', LPAD(k, 10, '0')),
       IF(n MOD 2 = 1, 'HYPER', 'MINI'),
       IF(k MOD 7 = 3, 'Y', 'N'),
       IF(k MOD 7 = 3, '2025-01-01 00:00:00', NULL),
       IF(k MOD 7 = 3, IF((k DIV 7) MOD 2 = 0, '2026-12-31 00:00:00', '2025-12-31 00:00:00'), NULL),
       IF(k MOD 11 = 5, 'N', 'Y')
  FROM x;

INSERT INTO t_소장현황 (분관번호, 도서번호, 갱신일시)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @hold_cnt
)
SELECT ((((n - 1) MOD @book_cnt) + 1 + ((n - 1) DIV @book_cnt) * 101) MOD 404) + 1,
       CONCAT('B', LPAD((n - 1) MOD @book_cnt + 1, 10, '0')),
       IF(n MOD 23 = 0,
          DATE_ADD('2026-01-19 10:27:00', INTERVAL (n DIV 23) MOD 240 SECOND),
          DATE_ADD('2025-10-01 00:00:00', INTERVAL FLOOR(RAND() * 5000000) SECOND))
  FROM r;

INSERT INTO t_분관도서대출 (도서번호, 분관번호, 대출정지여부, 정지기간제한여부, 정지시작일시, 정지종료일시)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @hold_cnt
)
SELECT CONCAT('B', LPAD((n - 1) MOD @book_cnt + 1, 10, '0')),
       ((((n - 1) MOD @book_cnt) + 1 + ((n - 1) DIV @book_cnt) * 101) MOD 404) + 1,
       CASE n MOD 20 WHEN 0 THEN 'Y' WHEN 1 THEN 'P' ELSE 'N' END,
       IF(n MOD 20 IN (0, 1) AND (n DIV 20) MOD 2 = 1, 'Y', 'N'),
       IF(n MOD 20 IN (0, 1) AND (n DIV 20) MOD 2 = 1, '2023-01-01 00:00:00', '2000-01-01 00:00:00'),
       IF(n MOD 20 IN (0, 1) AND (n DIV 20) MOD 2 = 1,
          IF((n DIV 40) MOD 2 = 0, '2026-12-31 00:00:00', '2023-12-31 00:00:00'),
          '2999-12-31 23:59:59')
  FROM r;

ANALYZE TABLE t_소장현황, t_도서, t_분관도서대출, t_도서서비스, t_분관;

SELECT COUNT(*) AS 소장현황건수 FROM t_소장현황;

SELECT COUNT(*) AS 도서건수 FROM t_도서;

SELECT COUNT(*) AS 분관도서대출건수 FROM t_분관도서대출;

SELECT COUNT(*) AS 도서서비스건수 FROM t_도서서비스;

SELECT COUNT(*) AS 분관건수 FROM t_분관;

SELECT COUNT(*) AS 조회구간_소장현황건수 FROM t_소장현황
 WHERE 갱신일시 >= '2026-01-19 10:27:00' AND 갱신일시 < '2026-01-19 10:31:00';

SELECT COUNT(*) AS 조건만족_분관건수 FROM t_분관
 WHERE 분관유형 = 'HYPER' AND 예약가능여부 = 'Y' AND 운영여부 = 'Y';


/* 15. 조인 조건의 함수 적용에 따른 실행계획 변경 : 튜닝 전/후 실행계획 비교 */
/* 특정 테이블을 선행 테이블로 변경하기 위해 임의로 인덱스를 사용하지 않도록 SQL을 수정하는 것은 다른 성능 문제를 발생시킬 수 있으므로 신중하게 접근해야 합니다.
건수, 버퍼 풀, 통계에 따라 달라 실습 환경에서는 다르게 나올 수 있습니다. */


EXPLAIN
SELECT h.도서번호 AS 도서번호
     , h.분관번호 AS 분관번호
     , h.갱신일시 AS 변경일시
  FROM t_소장현황 h
       INNER JOIN t_도서 b ON h.도서번호 = b.도서번호
       INNER JOIN t_분관도서대출 l ON h.도서번호 = l.도서번호 AND h.분관번호 = l.분관번호
       INNER JOIN t_도서서비스 s ON h.도서번호 = s.도서번호
       INNER JOIN t_분관 br ON h.분관번호 = br.분관번호
 WHERE h.갱신일시 >= '2026-01-19 10:27:00'
   AND h.갱신일시 <  '2026-01-19 10:31:00'
   AND b.자료유형 = 'TD'
   AND b.도서상태 = 'A'
   AND b.열람공개여부 = 'Y'
   AND IF(l.대출정지여부 IN ('Y', 'P')
          AND (l.정지기간제한여부 = 'N'
               OR l.정지기간제한여부 = 'Y' AND l.정지시작일시 <= '2026-01-19 10:27:00' AND '2024-01-19 10:31:00' <= l.정지종료일시), 'Y', 'N') = 'N'
   AND s.분관유형 = 'HYPER'
   AND s.예약가능여부 = 'Y'
   AND (s.서비스기간제한여부 = 'N'
        OR (s.서비스기간제한여부 = 'Y' AND '2026-01-19 10:27:00' BETWEEN s.서비스시작일시 AND s.서비스종료일시))
   AND br.분관유형 = 'HYPER'
   AND br.예약가능여부 = 'Y'
   AND br.운영여부 = 'Y';

-- 튜닝: ON h.분관번호 = br.분관번호  ->  ON TRIM(h.분관번호) = br.분관번호
--       (h 쪽 조인 컬럼에 함수를 적용해 br -> h 순서가 불가능하게 하고, h 를 선행 테이블로 유도)

-- < 튜닝 후 실행계획 > 조인 순서 h -> br -> s -> b -> l (h 는 idx_t_소장현황_01 range)
EXPLAIN
SELECT h.도서번호 AS 도서번호
     , h.분관번호 AS 분관번호
     , h.갱신일시 AS 변경일시
  FROM t_소장현황 h
       INNER JOIN t_도서 b ON h.도서번호 = b.도서번호
       INNER JOIN t_분관도서대출 l ON h.도서번호 = l.도서번호 AND h.분관번호 = l.분관번호
       INNER JOIN t_도서서비스 s ON h.도서번호 = s.도서번호
       INNER JOIN t_분관 br ON TRIM(h.분관번호) = br.분관번호
 WHERE h.갱신일시 >= '2026-01-19 10:27:00'
   AND h.갱신일시 <  '2026-01-19 10:31:00'
   AND b.자료유형 = 'TD'
   AND b.도서상태 = 'A'
   AND b.열람공개여부 = 'Y'
   AND IF(l.대출정지여부 IN ('Y', 'P')
          AND (l.정지기간제한여부 = 'N'
               OR l.정지기간제한여부 = 'Y' AND l.정지시작일시 <= '2026-01-19 10:27:00' AND '2024-01-19 10:31:00' <= l.정지종료일시), 'Y', 'N') = 'N'
   AND s.분관유형 = 'HYPER'
   AND s.예약가능여부 = 'Y'
   AND (s.서비스기간제한여부 = 'N'
        OR (s.서비스기간제한여부 = 'Y' AND '2026-01-19 10:27:00' BETWEEN s.서비스시작일시 AND s.서비스종료일시))
   AND br.분관유형 = 'HYPER'
   AND br.예약가능여부 = 'Y'
   AND br.운영여부 = 'Y';


/* 16. 스칼라 서브쿼리 튜닝 : t_마켓정산대사정보, t_업체마켓상품주문 실습 데이터 생성 (MySQL 8.0+) */

USE handbook;

-- 건수 조정: 아래 @m_cnt, @mpon_cnt 수정 (@m_cnt <= @mpon_cnt 유지, @mpon_cnt > @exp_cnt + @abc_cnt 유지)

SET @m_cnt      := 300000;   
SET @mpon_cnt   := 500000;  
SET @exp_cnt    := 185328;   
SET @abc_cnt    := 150000;   
SET @target_cnt := 1297;     
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_마켓정산대사정보;
CREATE TABLE t_마켓정산대사정보 (
  기준일자 varchar(8),
  상품주문번호 bigint,
  구분 char(1),
  주문옵션번호 bigint,
  사이트유형 varchar(10),
  PG입금예정일 varchar(8),
  마켓기준일자 varchar(8),
  마켓주문번호 varchar(20),
  마켓상품주문번호 varchar(25),
  대사진행상태 varchar(15),
  대사상태 char(2),
  PRIMARY KEY (기준일자, 상품주문번호, 구분, 주문옵션번호),
  KEY idx_t_마켓정산대사정보_01 (마켓주문번호, 마켓상품주문번호, 사이트유형),
  KEY idx_t_마켓정산대사정보_02 (PG입금예정일, 대사상태, 대사진행상태, 사이트유형)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_업체마켓상품주문;
CREATE TABLE t_업체마켓상품주문 (
  기준일자 varchar(8),
  사이트유형 varchar(10),
  마켓상품주문번호 varchar(20),
  마켓주문번호 varchar(20),
  구매확정일자 varchar(8),
  상품주문번호 bigint,
  PG입금예정일 varchar(8),
  PRIMARY KEY (기준일자, 사이트유형, 마켓상품주문번호, 상품주문번호),
  KEY idx_t_업체마켓상품주문_01 (사이트유형, PG입금예정일)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_업체마켓상품주문 (기준일자, 사이트유형, 마켓상품주문번호, 마켓주문번호, 구매확정일자, 상품주문번호, PG입금예정일)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @mpon_cnt
)
SELECT DATE_FORMAT(DATE_ADD('2026-03-01', INTERVAL (n MOD 60) DAY), '%Y%m%d'),
       CASE WHEN n <= @exp_cnt THEN 'EXP'
            WHEN n <= @exp_cnt + @abc_cnt THEN 'ABC'
            ELSE 'ETC' END,
       CONCAT('MP', LPAD(n, 10, '0')),
       CONCAT('MO', LPAD(n, 10, '0')),
       DATE_FORMAT(DATE_ADD('2026-03-01', INTERVAL (n MOD 60) + 3 DAY), '%Y%m%d'),
       n,
       DATE_FORMAT(DATE_ADD('2026-03-01', INTERVAL (n MOD 60) + 5 DAY), '%Y%m%d')
  FROM r;

INSERT INTO t_마켓정산대사정보 (기준일자, 상품주문번호, 구분, 주문옵션번호, 사이트유형, PG입금예정일, 마켓기준일자, 마켓주문번호, 마켓상품주문번호, 대사진행상태, 대사상태)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @m_cnt
)
SELECT DATE_FORMAT(DATE_ADD('2026-03-01', INTERVAL (n MOD 60) DAY), '%Y%m%d'),
       n,
       IF(n MOD 2 = 1, '1', '2'),
       1,
       CASE WHEN n <= @exp_cnt THEN 'EXP'
            WHEN n <= @exp_cnt + @abc_cnt THEN 'ABC'
            ELSE 'ETC' END,
       IF(n <= @target_cnt, '20260427',
          DATE_FORMAT(DATE_ADD('2026-04-01', INTERVAL (n MOD 60) DAY), '%Y%m%d')),
       DATE_FORMAT(DATE_ADD('2026-03-01', INTERVAL (n MOD 60) DAY), '%Y%m%d'),
       CONCAT('MO', LPAD(n, 10, '0')),
       CONCAT('MP', LPAD(n, 10, '0')),
       IF(n <= @target_cnt, 'MMISSION',
          ELT(n MOD 4 + 1, 'COMPLETE', 'WAIT', 'ERROR', 'MMISSION')),
       IF(n <= @target_cnt, 'NG',
          IF(n MOD 4 = 3, 'OK', 'NG'))
  FROM r;

ANALYZE TABLE t_마켓정산대사정보, t_업체마켓상품주문;

SELECT COUNT(*) AS 대사정보건수 FROM t_마켓정산대사정보;

SELECT COUNT(*) AS 상품주문건수 FROM t_업체마켓상품주문;

SELECT 사이트유형, COUNT(*) AS cnt FROM t_업체마켓상품주문 GROUP BY 사이트유형;

SELECT COUNT(*) AS 조회대상건수
  FROM t_마켓정산대사정보
 WHERE 사이트유형 = 'EXP' AND PG입금예정일 = '20260427' AND 대사진행상태 = 'MMISSION' AND 대사상태 = 'NG';


/* 16. 스칼라 서브쿼리 튜닝 : 튜닝 전/후 실행계획 비교 */

-- < 튜닝 전 실행계획 > mpon 테이블 key = idx_t_업체마켓상품주문_01 (사이트유형만 사용, key_len 32), rows 약 185,328
EXPLAIN
SELECT m.기준일자
     , m.구분
     , m.사이트유형
     , m.PG입금예정일
     , m.마켓주문번호
     , m.마켓상품주문번호
     , m.대사진행상태
     , m.대사상태
     , CASE WHEN m.사이트유형 IN ('ABC', 'EXP')
             AND m.구분 = '1' THEN m.마켓기준일자
            WHEN m.사이트유형 IN ('ABC', 'EXP')
             AND m.구분 = '2' THEN
            (
              SELECT mpon.구매확정일자
                FROM t_업체마켓상품주문 mpon
               WHERE mpon.사이트유형 = m.사이트유형
                 AND mpon.마켓주문번호 = m.마켓주문번호
                 AND mpon.마켓상품주문번호 = m.마켓상품주문번호
               GROUP BY mpon.구매확정일자
               LIMIT 1
            )
            ELSE ''
       END AS order_decision_dt
  FROM t_마켓정산대사정보 m
 WHERE m.사이트유형 = 'EXP'
   AND m.PG입금예정일 = '20260427'
   AND m.대사진행상태 = 'MMISSION'
   AND m.대사상태 = 'NG'
 ORDER BY m.구분
        , m.기준일자;


-- 튜닝: 스칼라 서브쿼리 WHERE 조건 컬럼으로 복합 인덱스 생성
--       (마켓상품주문번호 -> 마켓주문번호 -> 사이트유형 순서, 분포가 좋은 컬럼이 앞)

ALTER TABLE t_업체마켓상품주문 ADD KEY idx_t_업체마켓상품주문_02 (마켓상품주문번호, 마켓주문번호, 사이트유형);
ANALYZE TABLE t_업체마켓상품주문;

-- < 튜닝 후 실행계획 > mpon 테이블 key = idx_t_업체마켓상품주문_02 (key_len 156), rows = 1
EXPLAIN
SELECT m.기준일자
     , m.구분
     , m.사이트유형
     , m.PG입금예정일
     , m.마켓주문번호
     , m.마켓상품주문번호
     , m.대사진행상태
     , m.대사상태
     , CASE WHEN m.사이트유형 IN ('ABC', 'EXP')
             AND m.구분 = '1' THEN m.마켓기준일자
            WHEN m.사이트유형 IN ('ABC', 'EXP')
             AND m.구분 = '2' THEN
            (
              SELECT mpon.구매확정일자
                FROM t_업체마켓상품주문 mpon
               WHERE mpon.사이트유형 = m.사이트유형
                 AND mpon.마켓주문번호 = m.마켓주문번호
                 AND mpon.마켓상품주문번호 = m.마켓상품주문번호
               GROUP BY mpon.구매확정일자
               LIMIT 1
            )
            ELSE ''
       END AS order_decision_dt
  FROM t_마켓정산대사정보 m
 WHERE m.사이트유형 = 'EXP'
   AND m.PG입금예정일 = '20260427'
   AND m.대사진행상태 = 'MMISSION'
   AND m.대사상태 = 'NG'
 ORDER BY m.구분
        , m.기준일자;



/* 17. 서브쿼리 튜닝 : t_파트너잔액 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @pb_cnt, @pb_partner 수정

USE handbook;

SET @pb_cnt     := 453843; 
SET @pb_partner := 2000;  
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_파트너잔액;
CREATE TABLE t_파트너잔액 (
  기준일자 varchar(8),
  파트너아이디 varchar(20),
  결제정산합계 bigint,
  PRIMARY KEY (기준일자, 파트너아이디)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_파트너잔액 (기준일자, 파트너아이디, 결제정산합계)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @pb_cnt
)
SELECT DATE_FORMAT(DATE_ADD(DATE_SUB('2025-09-13', INTERVAL 113 DAY), INTERVAL ((n - 1) DIV @pb_partner) DAY), '%Y%m%d'),
       CONCAT('PT', LPAD((n - 1) MOD @pb_partner + 1, 6, '0')),
       FLOOR(RAND() * 10000000)
  FROM r;

ANALYZE TABLE t_파트너잔액;

SELECT COUNT(*) AS cnt FROM t_파트너잔액;

SELECT COUNT(*) AS 기준일자_20250913_미만 FROM t_파트너잔액 WHERE 기준일자 < '20250913';

SELECT MIN(기준일자) AS min_dt, MAX(기준일자) AS max_dt FROM t_파트너잔액;


/* 17. 서브쿼리 튜닝 : 튜닝 전/후 실행계획 비교 */

-- < 튜닝 전 실행계획 > pb1 테이블 type = ALL (FULL TABLE SCAN), pb2 = DEPENDENT SUBQUERY
EXPLAIN
SELECT '20250913' AS 기준일자
     , 파트너아이디
     , 결제정산합계
  FROM t_파트너잔액 pb1
 WHERE 기준일자 = (
                    SELECT MAX(기준일자)
                      FROM t_파트너잔액 pb2
                     WHERE pb1.파트너아이디 = pb2.파트너아이디
                       AND 기준일자 < '20250913');

-- 튜닝: 파트너별 최대 기준일자를 GROUP BY 로 한 번에 집계 후 (파트너아이디, 기준일자) IN 조건으로 조회

-- < 튜닝 후 실행계획 > pb1 테이블 type = range, key = PRIMARY (PRIMARY KEY RANGE SCAN), pb2 = Using temporary
EXPLAIN
SELECT '20250913' AS 기준일자
     , 파트너아이디
     , 결제정산합계
  FROM t_파트너잔액 pb1
 WHERE (파트너아이디, 기준일자) IN (
                                      SELECT 파트너아이디
                                           , MAX(기준일자) AS 기준일자
                                        FROM t_파트너잔액 pb2
                                       WHERE 기준일자 < '20250913'
                                       GROUP BY 파트너아이디
                                    )
   AND 기준일자 < '20250913';

/* 18. 복합 인덱스 컬럼 순서에 따른 성능 차이 : t_일별정산정보 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @dsi_cnt 수정

USE handbook;

SET @dsi_cnt  := 1000000;   
SET @dsi_slot := 913;       
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_일별정산정보;
CREATE TABLE t_일별정산정보 (
  정산번호 int,
  파트너아이디 varchar(20),
  기준일자 varchar(8),
  상품번호 varchar(25),
  상점유형 varchar(5),
  몰유형 char(2),
  정산금액 bigint,
  PRIMARY KEY (정산번호, 파트너아이디, 기준일자, 상품번호, 상점유형, 몰유형),
  KEY idx_t_일별정산정보_01 (기준일자, 몰유형),
  KEY idx_t_일별정산정보_02 (기준일자, 파트너아이디),
  KEY idx_t_일별정산정보_03 (기준일자, 상품번호)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_일별정산정보 (정산번호, 파트너아이디, 기준일자, 상품번호, 상점유형, 몰유형, 정산금액)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @dsi_cnt
), x AS (
  SELECT n,
         (n - 1) DIV @dsi_slot AS d,
         (n - 1) MOD @dsi_slot AS s
    FROM r
)
SELECT n,
       CASE WHEN s = 0 THEN IF(d MOD 15 = 0, '업체abc', '업체0000')
            ELSE CONCAT('업체', LPAD(s, 4, '0')) END,
       DATE_FORMAT(DATE_ADD('2023-01-01', INTERVAL d DAY), '%Y%m%d'),
       CONCAT('G', LPAD(n MOD 50000, 8, '0')),
       ELT(n MOD 3 + 1, 'S01', 'S02', 'S03'),
       ELT(n MOD 4 + 1, '01', '02', '03', '04'),
       FLOOR(RAND() * 1000000)
  FROM x;

ANALYZE TABLE t_일별정산정보;

SELECT COUNT(*) AS cnt FROM t_일별정산정보;

SELECT COUNT(*) AS 기준일자_범위_건수 FROM t_일별정산정보 WHERE 기준일자 >= '20250101' AND 기준일자 < '20250401';

SELECT COUNT(*) AS 업체abc_건수 FROM t_일별정산정보 WHERE 파트너아이디 = '업체abc' AND 기준일자 >= '20250101' AND 기준일자 < '20250401';


/* 18. 복합 인덱스 컬럼 순서에 따른 성능 차이 : 튜닝 전/후 실행계획 비교 */

-- 튜닝 전 상태로 되돌리기 (재실행용)
-- ALTER TABLE t_일별정산정보 DROP KEY idx_t_일별정산정보_04;

-- < 튜닝 전 실행계획 > key = idx_t_일별정산정보_01 (기준일자 범위만 사용), rows 가 매우 큼
-- (인덱스 선택은 통계에 따라 _02 / _03 이 될 수 있음. 기준일자 범위 전체를 읽는다는 점이 핵심)
EXPLAIN
SELECT DATE_FORMAT(CAST(dsi.기준일자 AS DATETIME), '%Y-%m-%d') AS 기준일자
     , dsi.정산금액
  FROM t_일별정산정보 dsi
 WHERE dsi.기준일자 >= '20250101'
   AND dsi.기준일자 < '20250401'
   AND dsi.파트너아이디 = '업체abc';

-- 튜닝: 등치(=) 조건 컬럼(파트너아이디)을 앞, 범위 조건 컬럼(기준일자)을 뒤로 하는 복합 인덱스 생성
ALTER TABLE t_일별정산정보 ADD KEY idx_t_일별정산정보_04 (파트너아이디, 기준일자);
ANALYZE TABLE t_일별정산정보;

-- < 튜닝 후 실행계획 > key = idx_t_일별정산정보_04, rows = 6
EXPLAIN
SELECT DATE_FORMAT(CAST(dsi.기준일자 AS DATETIME), '%Y-%m-%d') AS 기준일자
     , dsi.정산금액
  FROM t_일별정산정보 dsi
 WHERE dsi.기준일자 >= '20250101'
   AND dsi.기준일자 < '20250401'
   AND dsi.파트너아이디 = '업체abc';


/* 19. 복합 인덱스 컬럼을 활용한 JOIN 조건 개선 : t_구매주문, t_결제, t_클레임마스터, t_클레임정보, t_클레임상품, t_클레임추가금액, t_클레임배송 실습 데이터 생성 (MySQL 8.0+) */

USE handbook;

SET @claim_cnt    := 500000;     
SET @ca_claim_cnt := 199999;     
SET @ca_hot_cnt   := 200000;     
SET @claim_base   := 99500000;   
SET @target_no    := 387766;    
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_구매주문;
CREATE TABLE t_구매주문 (
  구매주문번호 BIGINT,
  결제번호 BIGINT,
  고객번호 BIGINT,
  PRIMARY KEY (구매주문번호),
  KEY idx_t_구매주문_01 (고객번호),
  KEY idx_t_구매주문_02 (결제번호)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_결제;
CREATE TABLE t_결제 (
  결제번호 BIGINT,
  결제완료일자 DATETIME,
  PRIMARY KEY (결제번호),
  KEY idx_t_결제_01 (결제완료일자)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_클레임마스터;
CREATE TABLE t_클레임마스터 (
  클레임번호 BIGINT,
  구매주문번호 BIGINT,
  부분취소여부 CHAR(1),
  완료금액 BIGINT,
  PRIMARY KEY (클레임번호),
  KEY idx_t_클레임마스터_01 (구매주문번호, 부분취소여부)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_클레임정보;
CREATE TABLE t_클레임정보 (
  클레임번호 BIGINT,
  상품주문번호 BIGINT,
  상품번호 VARCHAR(25),
  배송번호 BIGINT,
  구매주문번호 BIGINT,
  결제완료일시 DATETIME,
  PRIMARY KEY (클레임번호, 상품주문번호, 상품번호, 배송번호),
  KEY idx_t_클레임정보_01 (구매주문번호, 상품번호, 상품주문번호),
  KEY idx_t_클레임정보_02 (구매주문번호, 배송번호),
  KEY idx_t_클레임정보_03 (결제완료일시)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_클레임상품;
CREATE TABLE t_클레임상품 (
  클레임상품번호 BIGINT,
  클레임번호 BIGINT,
  클레임배송번호 BIGINT,
  구매주문번호 BIGINT,
  상품주문번호 BIGINT,
  PRIMARY KEY (클레임상품번호),
  KEY idx_t_클레임상품_01 (클레임번호, 구매주문번호, 클레임배송번호),
  KEY idx_t_클레임상품_02 (클레임번호, 클레임배송번호),
  KEY idx_t_클레임상품_03 (상품주문번호)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_클레임추가금액;
CREATE TABLE t_클레임추가금액 (
  클레임추가금액번호 BIGINT,
  클레임번호 BIGINT,
  클레임배송번호 BIGINT,
  구매주문번호 BIGINT,
  배송번호 BIGINT,
  상품주문번호 BIGINT,
  상품번호 VARCHAR(25),
  추가금액유형 CHAR(1),
  추가금액유형상세 VARCHAR(20),
  추가총금액 BIGINT,
  PRIMARY KEY (클레임추가금액번호),
  KEY idx_t_클레임추가금액_01 (클레임번호, 클레임배송번호, 추가금액유형상세, 추가금액유형),
  KEY idx_t_클레임추가금액_02 (구매주문번호, 배송번호, 클레임번호, 추가금액유형상세),
  KEY idx_t_클레임추가금액_03 (상품주문번호, 상품번호, 추가금액유형, 추가금액유형상세),
  KEY idx_t_클레임추가금액_04 (배송번호, 추가금액유형상세)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_클레임배송;
CREATE TABLE t_클레임배송 (
  클레임배송번호 BIGINT,
  클레임번호 BIGINT,
  클레임유형 CHAR(1),
  PRIMARY KEY (클레임배송번호),
  KEY idx_t_클레임배송_01 (클레임번호, 클레임유형)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_결제 (결제번호, 결제완료일자)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @claim_cnt
)
SELECT n,
       DATE_ADD('2025-01-01', INTERVAL n MINUTE)
  FROM r;

INSERT INTO t_구매주문 (구매주문번호, 결제번호, 고객번호)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @claim_cnt
)
SELECT n,
       n,
       IF(n = @target_no, 12345678, 10000000 + n MOD 100000)
  FROM r;

INSERT INTO t_클레임마스터 (클레임번호, 구매주문번호, 부분취소여부, 완료금액)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @claim_cnt
)
SELECT @claim_base + n,
       n,
       IF(n MOD 5 = 0, 'Y', 'N'),
       FLOOR(RAND() * 100000)
  FROM r;

INSERT INTO t_클레임정보 (클레임번호, 상품주문번호, 상품번호, 배송번호, 구매주문번호, 결제완료일시)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @claim_cnt
)
SELECT @claim_base + n,
       60000000 + n,
       CONCAT('G', LPAD(n, 10, '0')),
       70000000 + n,
       n,
       DATE_ADD('2025-01-01', INTERVAL n MINUTE)
  FROM r;

INSERT INTO t_클레임정보 (클레임번호, 상품주문번호, 상품번호, 배송번호, 구매주문번호, 결제완료일시)
VALUES (@claim_base + @target_no, 69000000 + @target_no, CONCAT('G9', LPAD(@target_no, 9, '0')),
        70000000 + @target_no, @target_no, DATE_ADD('2025-01-01', INTERVAL @target_no MINUTE));

INSERT INTO t_클레임상품 (클레임상품번호, 클레임번호, 클레임배송번호, 구매주문번호, 상품주문번호)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @claim_cnt
)
SELECT n,
       @claim_base + n,
       70000000 + n,
       n,
       60000000 + n
  FROM r;

INSERT INTO t_클레임상품 (클레임상품번호, 클레임번호, 클레임배송번호, 구매주문번호, 상품주문번호)
VALUES (@claim_cnt + 1, @claim_base + @target_no, 70000000 + @target_no, @target_no, 69000000 + @target_no);

INSERT INTO t_클레임배송 (클레임배송번호, 클레임번호, 클레임유형)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @claim_cnt
)
SELECT 70000000 + n,
       @claim_base + n,
       ELT(n MOD 3 + 1, 'R', 'E', 'C')
  FROM r;

INSERT INTO t_클레임추가금액 (클레임추가금액번호, 클레임번호, 클레임배송번호, 구매주문번호, 배송번호, 상품주문번호, 상품번호, 추가금액유형, 추가금액유형상세, 추가총금액)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @ca_claim_cnt * 4
), x AS (
  SELECT n,
         (n - 1) DIV 4 + 1 AS c,
         (n - 1) MOD 4     AS k
    FROM r
)
SELECT n,
       @claim_base + c,
       70000000 + c,
       c,
       70000000 + c,
       CASE k WHEN 0 THEN 60000000 + c
              WHEN 1 THEN 66000000 + c
              WHEN 2 THEN 67000000 + c
              ELSE 68000000 + c END,
       CASE k WHEN 0 THEN CONCAT('G', LPAD(c, 10, '0'))
              ELSE CONCAT('G', k, LPAD(c, 9, '0')) END,
       'C',
       IF(k < 2, 'coupon_1', 'coupon_2'),
       FLOOR(RAND() * 10000)
  FROM x;

INSERT INTO t_클레임추가금액 (클레임추가금액번호, 클레임번호, 클레임배송번호, 구매주문번호, 배송번호, 상품주문번호, 상품번호, 추가금액유형, 추가금액유형상세, 추가총금액)
VALUES (9000001, @claim_base + @target_no, 70000000 + @target_no, @target_no, 70000000 + @target_no,
        60000000 + @target_no, CONCAT('G', LPAD(@target_no, 10, '0')), 'C', 'coupon_1', 1000),
       (9000002, @claim_base + @target_no, 70000000 + @target_no, @target_no, 70000000 + @target_no,
        69000000 + @target_no, CONCAT('G9', LPAD(@target_no, 9, '0')), 'C', 'coupon_1', 2000),
       (9000003, @claim_base + @target_no, 70000000 + @target_no, @target_no, 70000000 + @target_no,
        66000000 + @target_no, CONCAT('G1', LPAD(@target_no, 9, '0')), 'C', 'coupon_2', 300),
       (9000004, @claim_base + @target_no, 70000000 + @target_no, @target_no, 70000000 + @target_no,
        67000000 + @target_no, CONCAT('G2', LPAD(@target_no, 9, '0')), 'C', 'coupon_2', 400);

INSERT INTO t_클레임추가금액 (클레임추가금액번호, 클레임번호, 클레임배송번호, 구매주문번호, 배송번호, 상품주문번호, 상품번호, 추가금액유형, 추가금액유형상세, 추가총금액)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @ca_hot_cnt
)
SELECT 10000000 + n,
       800000000 + n,
       800000000 + n,
       800000000 + n,
       800000000 + n,
       60000000 + @target_no,
       CONCAT('H', LPAD(n, 10, '0')),
       'C',
       ELT(n MOD 3 + 1, 'coupon_1', 'coupon_2', 'coupon_3'),
       FLOOR(RAND() * 10000)
  FROM r;

ANALYZE TABLE t_구매주문, t_결제, t_클레임마스터, t_클레임정보, t_클레임상품, t_클레임추가금액, t_클레임배송;

SELECT COUNT(*) AS 클레임추가금액건수 FROM t_클레임추가금액;

SELECT COUNT(*) AS 편중_상품주문번호_건수 FROM t_클레임추가금액 WHERE 상품주문번호 = 60387766;

SELECT cm.클레임번호, po.고객번호, ci.상품주문번호, ci.상품번호, ci.배송번호
  FROM t_클레임마스터 cm
  JOIN t_구매주문 po ON po.구매주문번호 = cm.구매주문번호
  JOIN t_클레임정보 ci ON ci.클레임번호 = cm.클레임번호
 WHERE cm.클레임번호 = 99887766;


/* 19. 복합 인덱스 컬럼을 활용한 JOIN 조건 개선 : 튜닝 전/후 실행계획 비교 */
-- 인덱스 변경 없이 JOIN 조건만 추가하는 사례 (재실행용 되돌리기 작업 불필요)
-- 두 실행계획의 key 는 동일하게 보일 수 있음. ca 의 key_len / ref 와 실제 읽는 건수가 달라지는 것을 확인

EXPLAIN
SELECT cm.클레임번호
     , ci.결제완료일시 AS 결제완료일시
     , cm.완료금액 AS 완료금액
     , p.결제완료일자
     , (SELECT max(cb.클레임유형)
          FROM t_클레임배송 cb
         WHERE cb.클레임번호 = cm.클레임번호) AS 클레임구분
  FROM t_구매주문 po
 INNER JOIN t_결제 p ON po.결제번호 = p.결제번호
 INNER JOIN t_클레임마스터 cm ON cm.구매주문번호 = po.구매주문번호
 INNER JOIN t_클레임정보 ci ON ci.클레임번호 = cm.클레임번호
  LEFT OUTER JOIN t_클레임상품 citem ON citem.클레임번호 = ci.클레임번호
                                    AND citem.상품주문번호 = ci.상품주문번호
  LEFT OUTER JOIN t_클레임추가금액 ca ON ca.클레임번호 = ci.클레임번호
                                     AND ca.구매주문번호 = ci.구매주문번호
                                     AND ca.배송번호 = ci.배송번호
                                     AND ca.상품주문번호 = ci.상품주문번호
                                     AND ca.추가금액유형상세 = 'coupon_1'
  LEFT OUTER JOIN t_클레임추가금액 ca2 ON ca2.클레임번호 = ci.클레임번호
                                      AND ca2.구매주문번호 = ci.구매주문번호
                                      AND ca2.배송번호 = ci.배송번호
                                      AND ca2.추가금액유형상세 = 'coupon_2'
 WHERE cm.클레임번호 = 99887766
   AND po.고객번호 = 12345678;


-- < 튜닝 후 실행계획 > ca 테이블 key 는 동일, ref = ci.상품주문번호, ci.상품번호 (key_len 증가)
EXPLAIN
SELECT cm.클레임번호
     , ci.결제완료일시 AS 결제완료일시
     , cm.완료금액 AS 완료금액
     , p.결제완료일자
     , (SELECT max(cb.클레임유형)
          FROM t_클레임배송 cb
         WHERE cb.클레임번호 = cm.클레임번호) AS 클레임구분
  FROM t_구매주문 po
 INNER JOIN t_결제 p ON po.결제번호 = p.결제번호
 INNER JOIN t_클레임마스터 cm ON cm.구매주문번호 = po.구매주문번호
 INNER JOIN t_클레임정보 ci ON ci.클레임번호 = cm.클레임번호
  LEFT OUTER JOIN t_클레임상품 citem ON citem.클레임번호 = ci.클레임번호
                                    AND citem.상품주문번호 = ci.상품주문번호
  LEFT OUTER JOIN t_클레임추가금액 ca ON ca.클레임번호 = ci.클레임번호
                                     AND ca.구매주문번호 = ci.구매주문번호
                                     AND ca.배송번호 = ci.배송번호
                                     AND ca.상품주문번호 = ci.상품주문번호
                                     AND ca.추가금액유형상세 = 'coupon_1'
                                     AND ca.상품번호 = ci.상품번호                               
  LEFT OUTER JOIN t_클레임추가금액 ca2 ON ca2.클레임번호 = ci.클레임번호
                                      AND ca2.구매주문번호 = ci.구매주문번호
                                      AND ca2.배송번호 = ci.배송번호
                                      AND ca2.추가금액유형상세 = 'coupon_2'
 WHERE cm.클레임번호 = 99887766
   AND po.고객번호 = 12345678;



/* 20. 장애 사례 ① LEFT JOIN 서브쿼리 추가 후 CPU 100% 발생, 원인 파악과 튜닝 : t_온라인행사, t_온라인행사상품, t_온라인행사점포 실습 데이터 생성 (MySQL 8.0+) */

-- 건수 조정: 아래 @event_cnt, @item_cnt, @store_cnt 수정

USE handbook;

SET @event_cnt := 1377;
SET @item_cnt  := 1401;
SET @store_cnt := 8766;
SET @store_per_event := 46;   
SET SESSION cte_max_recursion_depth = 1000000;

DROP TABLE IF EXISTS t_온라인행사;
CREATE TABLE t_온라인행사 (
  온라인행사ID int AUTO_INCREMENT,
  행사구성상세ID bigint,
  할인금액 int,
  행사시작일시 datetime,
  행사종료일시 datetime,
  사용여부 char(1),
  PRIMARY KEY (온라인행사ID),
  KEY idx_t_온라인행사_01 (행사시작일시, 행사종료일시, 사용여부),
  KEY idx_t_온라인행사_02 (행사구성상세ID, 행사시작일시, 행사종료일시),
  KEY idx_t_온라인행사_03 (행사종료일시, 행사시작일시, 사용여부)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_온라인행사상품;
CREATE TABLE t_온라인행사상품 (
  온라인행사ID int,
  상품번호 varchar(25),
  사용여부 char(1),
  PRIMARY KEY (온라인행사ID, 상품번호)
) DEFAULT CHARSET=utf8mb3;

DROP TABLE IF EXISTS t_온라인행사점포;
CREATE TABLE t_온라인행사점포 (
  행사구성상세ID int,
  점포ID int,
  온라인행사ID int,
  사용여부 char(1),
  PRIMARY KEY (행사구성상세ID, 점포ID, 온라인행사ID),
  KEY idx_t_온라인행사점포_01 (온라인행사ID, 사용여부),
  KEY idx_t_온라인행사점포_02 (행사구성상세ID, 점포ID, 사용여부)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_온라인행사 (온라인행사ID, 행사구성상세ID, 할인금액, 행사시작일시, 행사종료일시, 사용여부)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @event_cnt
)
SELECT n,
       100000 + n,
       (1 + n MOD 10) * 1000,
       CASE WHEN n MOD 100 < 89 THEN DATE_SUB(NOW(), INTERVAL (n MOD 30 + 1) DAY)
            ELSE DATE_SUB(NOW(), INTERVAL (n MOD 30 + 90) DAY) END,
       CASE WHEN n MOD 100 < 89 THEN DATE_ADD(NOW(), INTERVAL (n MOD 30 + 30) DAY)
            ELSE DATE_SUB(NOW(), INTERVAL (n MOD 30 + 31) DAY) END,
       IF(n MOD 25 = 0, 'N', 'Y')
  FROM r;

INSERT INTO t_온라인행사상품 (온라인행사ID, 상품번호, 사용여부)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @item_cnt
)
SELECT IF(n <= @event_cnt, n, n - @event_cnt),
       CASE n
         WHEN 1  THEN '12345'
         WHEN 2  THEN '12345678'
         WHEN 3  THEN '1111111'
         WHEN 4  THEN '2222222'
         WHEN 5  THEN '333333'
         WHEN 6  THEN '44444'
         WHEN 7  THEN '5555'
         WHEN 8  THEN '666666'
         WHEN 9  THEN '12345'
         WHEN 10 THEN '333333'
         ELSE CAST(1000000 + n AS CHAR)
       END,
       'Y'
  FROM r;

INSERT INTO t_온라인행사점포 (행사구성상세ID, 점포ID, 온라인행사ID, 사용여부)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @store_cnt
)
SELECT 100000 + (n - 1) DIV @store_per_event + 1,
       (n - 1) MOD @store_per_event + 1,
       (n - 1) DIV @store_per_event + 1,
       IF(n > (@store_cnt DIV @store_per_event) * @store_per_event, 'N', 'Y')
  FROM r;

ANALYZE TABLE t_온라인행사, t_온라인행사상품, t_온라인행사점포;

SELECT COUNT(*) AS 행사건수 FROM t_온라인행사;

SELECT COUNT(*) AS 행사상품건수 FROM t_온라인행사상품;

SELECT COUNT(*) AS 행사점포건수 FROM t_온라인행사점포;


/* 20. 장애 사례 ① LEFT JOIN 서브쿼리 추가 후 CPU 100% 발생, 원인 파악과 튜닝 : 튜닝 전/후 실행계획 비교 */

-- 튜닝 전 상태로 되돌리기 (재실행용)
-- ALTER TABLE t_온라인행사상품 DROP KEY idx_t_온라인행사상품_01;

-- < 튜닝 전 실행계획 > errpi 테이블 type = ALL (FULL TABLE SCAN, rows 약 1,401)
EXPLAIN
SELECT errp.행사구성상세ID
     , errp.온라인행사ID
     , errp.할인금액
     , errpi.상품번호
     , errpi.사용여부
     , errps.점포ID
  FROM t_온라인행사 errp
       INNER JOIN t_온라인행사점포 errps ON errp.온라인행사ID = errps.온라인행사ID AND errps.사용여부 = 'Y'
       INNER JOIN t_온라인행사상품 errpi ON errp.온라인행사ID = errpi.온라인행사ID
 WHERE NOW() BETWEEN errp.행사시작일시 AND errp.행사종료일시
   AND errp.사용여부 = 'Y';

-- 튜닝: 상품번호 인덱스 추가 + 서브쿼리에 바깥 WHERE 절과 동일한 상품번호 조건 추가
-- (참고: 가능하면 PRIMARY KEY (상품번호, 온라인행사ID) 로 변경하고 온라인행사ID 를 인덱스로 추가하는 방법도 있음)
ALTER TABLE t_온라인행사상품 ADD KEY idx_t_온라인행사상품_01 (상품번호);
ANALYZE TABLE t_온라인행사상품;

-- < 튜닝 후 실행계획 > errpi 테이블 type = range, key = idx_t_온라인행사상품_01 (rows 약 10)
EXPLAIN
SELECT errp.행사구성상세ID
     , errp.온라인행사ID
     , errp.할인금액
     , errpi.상품번호
     , errpi.사용여부
     , errps.점포ID
  FROM t_온라인행사 errp
       INNER JOIN t_온라인행사점포 errps ON errp.온라인행사ID = errps.온라인행사ID AND errps.사용여부 = 'Y'
       INNER JOIN t_온라인행사상품 errpi ON errp.온라인행사ID = errpi.온라인행사ID
 WHERE NOW() BETWEEN errp.행사시작일시 AND errp.행사종료일시
   AND errp.사용여부 = 'Y'
   AND errpi.상품번호 IN ('12345', '12345678', '1111111', '2222222', '333333', '44444', '5555', '666666');


/* 21. 장애 사례 ② 선착순 이벤트 CPU 100% 발생, 원인 파악과 튜닝 : t_데일리추첨마일리지이력 실습 데이터 생성 (MySQL 8.0+) */

-- 건수 조정: 아래 @cnt 수정 (@cnt >= @evt1_total 유지)
-- 적재 시 데일리참여일은 실행 시점의 오늘 날짜(CURDATE) 기준이므로, 적재 당일에 EXPLAIN 을 실행해야 함

USE handbook;

SET @cnt := 1000000;              
SET @evt1_today_b26   := 72500;   
SET @evt1_today_other := 100;     
SET @evt1_past_b26    := 15426;   
SET @evt1_total       := 159000;  
SET @b1 := @evt1_today_b26;
SET @b2 := @b1 + @evt1_today_other;
SET @b3 := @b2 + @evt1_past_b26;
SET SESSION cte_max_recursion_depth = 1000000;

-- 튜닝 전 상태 : 인덱스 3개 (PK, uk_01, idx_01). 인덱스는 적재 후 생성
DROP TABLE IF EXISTS t_데일리추첨마일리지이력;
CREATE TABLE t_데일리추첨마일리지이력 (
  일련번호 bigint,
  이벤트코드 varchar(11),
  이벤트혜택일련번호 bigint,
  당첨회원번호 bigint,
  데일리참여일 varchar(20),
  등록일시 datetime,
  PRIMARY KEY (일련번호)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_데일리추첨마일리지이력 (일련번호, 이벤트코드, 이벤트혜택일련번호, 당첨회원번호, 데일리참여일, 등록일시)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @cnt
),
s AS (
  SELECT n,
         CASE WHEN n <= @evt1_total THEN 'EVT-001'
              ELSE CONCAT('EVT-', LPAD(2 + n MOD 49, 3, '0')) END AS evt,
         CASE WHEN n <= @b1 THEN 26
              WHEN n <= @b2 THEN 27
              WHEN n <= @b3 THEN 26
              WHEN n <= @evt1_total THEN 1 + n MOD 25
              ELSE 1 + n MOD 30 END AS ben,
         CASE WHEN n <= @b2 THEN 0
              WHEN n <= @b3 THEN 1 + n MOD 30
              WHEN n <= @evt1_total THEN 1 + n MOD 60
              ELSE n MOD 60 END AS d
    FROM r
)
SELECT n,
       evt,
       ben,
       100000000 + n,
       DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL d DAY), '%Y-%m-%d'),
       DATE_SUB(DATE_SUB(NOW(), INTERVAL d DAY), INTERVAL n MOD 3600 SECOND)
  FROM s;

-- 인덱스는 적재 후 생성 (적재 속도 향상) : 튜닝 전 상태
ALTER TABLE t_데일리추첨마일리지이력
  ADD UNIQUE KEY uk_t_데일리추첨마일리지이력_01 (이벤트코드, 당첨회원번호, 데일리참여일),
  ADD KEY idx_t_데일리추첨마일리지이력_01 (이벤트코드, 이벤트혜택일련번호);

ANALYZE TABLE t_데일리추첨마일리지이력;

SELECT COUNT(*) AS cnt FROM t_데일리추첨마일리지이력;

SELECT COUNT(*) AS evt1_cnt FROM t_데일리추첨마일리지이력 WHERE 이벤트코드 = 'EVT-001';

SELECT COUNT(*) AS evt1_b26_cnt FROM t_데일리추첨마일리지이력 WHERE 이벤트코드 = 'EVT-001' AND 이벤트혜택일련번호 = 26;

SELECT COUNT(*) AS evt1_today_cnt FROM t_데일리추첨마일리지이력 WHERE 이벤트코드 = 'EVT-001' AND 데일리참여일 = date_format(now(), '%Y-%m-%d');


/* 21. 장애 사례 ② 선착순 이벤트 CPU 100% 발생, 원인 파악과 튜닝 : 튜닝 전/후 실행계획 비교 */

-- 튜닝 전 상태로 되돌리기 (재실행용)
-- ALTER TABLE t_데일리추첨마일리지이력 DROP KEY idx_t_데일리추첨마일리지이력_02, DROP KEY idx_t_데일리추첨마일리지이력_03;

-- < 튜닝 전 실행계획 > 쿼리 ①: idx_01 (이벤트코드, 이벤트혜택일련번호) 사용, rows 약 87,926
EXPLAIN
SELECT count(*) AS cnt
  FROM t_데일리추첨마일리지이력
 WHERE 이벤트코드 = 'EVT-001'
   AND 이벤트혜택일련번호 = 26
   AND 데일리참여일 = date_format(now(), '%Y-%m-%d');

-- < 튜닝 전 실행계획 > 쿼리 ②: 이벤트코드만 인덱스 조건으로 사용, rows 약 159,000
-- (책 설명: uk 인덱스가 사용되었지만 당첨회원번호 조건이 없어 이벤트코드만 탐색 조건. 옵티마이저에 따라 idx_01 이 선택될 수도 있음)
EXPLAIN
SELECT count(*) AS cnt
  FROM t_데일리추첨마일리지이력
 WHERE 이벤트코드 = 'EVT-001'
   AND 데일리참여일 = date_format(now(), '%Y-%m-%d');


-- 튜닝: 조건 컬럼을 모두 인덱스에 포함
-- (INSERT 부하가 큰 테이블이면 (이벤트코드, 데일리참여일, 이벤트혜택일련번호) 인덱스 1개만 만들어 사용하기도 함)
ALTER TABLE t_데일리추첨마일리지이력
  ADD KEY idx_t_데일리추첨마일리지이력_02 (이벤트코드, 이벤트혜택일련번호, 데일리참여일),
  ADD KEY idx_t_데일리추첨마일리지이력_03 (이벤트코드, 데일리참여일);
ANALYZE TABLE t_데일리추첨마일리지이력;

-- < 튜닝 후 실행계획 > 쿼리 ①: key = idx_02 (ref const,const,const), rows 약 72,500
EXPLAIN
SELECT count(*) AS cnt
  FROM t_데일리추첨마일리지이력
 WHERE 이벤트코드 = 'EVT-001'
   AND 이벤트혜택일련번호 = 26
   AND 데일리참여일 = date_format(now(), '%Y-%m-%d');

-- < 튜닝 후 실행계획 > 쿼리 ②: key = idx_03 (ref const,const), rows 약 72,600
EXPLAIN
SELECT count(*) AS cnt
  FROM t_데일리추첨마일리지이력
 WHERE 이벤트코드 = 'EVT-001'
   AND 데일리참여일 = date_format(now(), '%Y-%m-%d');



/* 22. SQL 튜닝을 통한 성능 개선과 비용 절감 사례 : t_재고관리 실습 데이터 생성 (MySQL 8.0+) */
-- 건수 조정: 아래 @cnt 수정 (@cnt >= @target_cnt 유지)

USE handbook;

SET @cnt := 1000000;         
SET @target_cnt := 41170;     
SET SESSION cte_max_recursion_depth = 1000000;

-- 튜닝 전 상태 : idx_t_재고관리_01 (상품번호, 마켓유형) 만 존재. 인덱스는 적재 후 생성
DROP TABLE IF EXISTS t_재고관리;
CREATE TABLE t_재고관리 (
  시퀀스 bigint,
  마켓유형 varchar(20),
  점포유형 varchar(20),
  점포코드 int,
  상품번호 varchar(30),
  수량 int,
  사용여부 char(1),
  변경일자 datetime,
  PRIMARY KEY (시퀀스)
) DEFAULT CHARSET=utf8mb3;

INSERT INTO t_재고관리 (시퀀스, 마켓유형, 점포유형, 점포코드, 상품번호, 수량, 사용여부, 변경일자)
WITH RECURSIVE r (n) AS (
  SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < @cnt
),
s AS (
  SELECT n,
         IF(n <= @target_cnt, n, 1 + n MOD @target_cnt) AS store_cd
    FROM r
)
SELECT n,
       'OOO즉시배송',
       ELT(1 + store_cd MOD 4, '익스프레스', '슈퍼', '하이퍼', '마트'),
       store_cd,
       IF(n <= @target_cnt, '1234567', CAST(1000000 + n MOD 20000 AS CHAR)),
       FLOOR(RAND() * 1000),
       IF(n <= @target_cnt OR n MOD 10 <> 0, 'Y', 'N'),
       DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND() * 43200000) SECOND)
  FROM s;

-- 인덱스는 적재 후 생성 (적재 속도 향상) : 튜닝 전 상태
ALTER TABLE t_재고관리 ADD KEY idx_t_재고관리_01 (상품번호, 마켓유형);

ANALYZE TABLE t_재고관리;

SELECT COUNT(*) AS cnt FROM t_재고관리;

SELECT COUNT(*) AS 대상상품_즉시배송 FROM t_재고관리 WHERE 상품번호 = '1234567' AND 마켓유형 = 'OOO즉시배송';

SELECT 시퀀스, 마켓유형, 점포유형, 점포코드, 상품번호, 사용여부
  FROM t_재고관리
 WHERE 마켓유형 = 'OOO즉시배송' AND 점포유형 = '익스프레스' AND 점포코드 = 4000 AND 상품번호 = '1234567' AND 사용여부 = 'Y';


/* 22. SQL 튜닝을 통한 성능 개선과 비용 절감 사례 : 튜닝 전/후 실행계획 비교 */
-- 튜닝 전 상태로 되돌리기 (재실행용)
-- ALTER TABLE t_재고관리 DROP KEY idx_t_재고관리_02;

-- < 튜닝 전 실행계획 > type = range, key = idx_t_재고관리_01 (상품번호, 마켓유형), rows 약 41,170
EXPLAIN
UPDATE t_재고관리
   SET 사용여부 = 'N', 변경일자 = NOW()
 WHERE 마켓유형 = 'OOO즉시배송'
   AND 점포유형 = '익스프레스'
   AND 점포코드 = 4000
   AND 상품번호 = '1234567'
   AND 사용여부 = 'Y';

-- 튜닝: WHERE 조건값으로 데이터 분포 확인 후 효율이 좋은 컬럼 순서로 복합 인덱스 생성
-- (점포코드 -> 상품번호 -> 사용여부 -> 마켓유형)
-- 기대 결과: 점포코드_종류 41170 > 상품번호_종류 20001 > 사용여부_종류 2 > 마켓유형_종류 1
SELECT COUNT(DISTINCT 점포코드) AS 점포코드_종류,
       COUNT(DISTINCT 상품번호) AS 상품번호_종류,
       COUNT(DISTINCT 사용여부) AS 사용여부_종류,
       COUNT(DISTINCT 마켓유형) AS 마켓유형_종류
  FROM t_재고관리;

ALTER TABLE t_재고관리 ADD KEY idx_t_재고관리_02 (점포코드, 상품번호, 사용여부, 마켓유형);
ANALYZE TABLE t_재고관리;

-- < 튜닝 후 실행계획 > type = range, key = idx_t_재고관리_02, ref = const,const,const,const, rows 1
EXPLAIN
UPDATE t_재고관리
   SET 사용여부 = 'N', 변경일자 = NOW()
 WHERE 마켓유형 = 'OOO즉시배송'
   AND 점포유형 = '익스프레스'
   AND 점포코드 = 4000
   AND 상품번호 = '1234567'
   AND 사용여부 = 'Y';

