use trips_db;
select * from dim_City;
select * from dim_date;
select * from dim_repeat_trip_distribution;
select * from fact_passenger_summary;
select * from trips_db.fact_trips;

-- Business Request 1: City-Level Fare and Trip -Summary Report
with summary as(
select c.city_name as city_name,t.city_id,count(t.trip_id) as total_trips,sum(t.distance_travelled_km) as total_distance, 
sum(t.fare_amount) as total_fare 
from dim_city as c
join fact_trips as t
on c.city_id=t.city_id 
group by t.city_id)
select city_name, 
total_trips, 
round((total_fare/total_distance),2) as avg_fare_per_km, 
round((total_fare/total_trips),2) as avg_fare_per_trip,
concat(round((total_trips/(select count(*) from fact_trips)*100),2),'%') as citytrip_contribution_to_totaltrips
from summary
order by avg_fare_per_trip;


-- Business Request 2:Monthly level trips target performance report.
With trips_with_month As (
    select 
        city_id,
        trip_id,
        month(date) as month_no
    from trips_db.fact_trips
),
actual_Vs_Target As (
    select 
        c.city_name as city_name,
        t.city_id,
        t.month_no,
        count(t.trip_id) as Actual_trips,
        tt.total_target_trips as target_trips
    from trips_with_month as t
    join trips_db.dim_city as c
        on c.city_id = t.city_id
    join targets_db.monthly_target_trips as tt
        on t.city_id = tt.city_id 
        and t.month_no = month(tt.month)
    group by t.city_id, t.month_no, c.city_name, tt.total_target_trips
)
select *, 
       case 
           when actual_trips > target_trips then "Above Target" 
           else "Below Target" 
       end as performance_status,
       concat(
           round(((actual_trips - target_trips) / target_trips) * 100, 2), 
           '%'
       ) as Percentage_Diff
from actual_Vs_Target;




-- Business Request 3:City Level Repeat Passenger Trip Report.

SELECT 
    city_name,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '2-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `2-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '3-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `3-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '4-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `4-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '5-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `5-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '6-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `6-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '7-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `7-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '8-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `8-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '9-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `9-Trips`,
    CONCAT(ROUND(SUM(CASE WHEN trip_count = '10-Trips' THEN repeat_passenger_count ELSE 0 END) / MAX(city_total) * 100, 2), '%') AS `10-Trips`
FROM (
    SELECT 
        city.city_name,
        trip.city_id,
        trip.trip_count,
        trip.repeat_passenger_count,
        SUM(trip.repeat_passenger_count) OVER (PARTITION BY trip.city_id) AS city_total
    FROM 
        dim_city AS city
    JOIN
        dim_repeat_trip_distribution AS trip
        ON city.city_id = trip.city_id
) result
GROUP BY city_name;


   -- Business Request 4:Identify cities with highest and lowest total new passengers 
WITH City_rnk_list AS (
    SELECT 
        c.city_name AS city_name, 
        SUM(f.new_passengers) AS new_passengers,
        RANK() OVER (ORDER BY SUM(f.new_passengers) DESC) AS rnk
    FROM 
        dim_city AS c
    JOIN 
        fact_passenger_summary AS f
    ON 
        c.city_id = f.city_id
    GROUP BY 
        c.city_name
),
Categorized_Cities AS (
    SELECT 
        city_name, 
        new_passengers, 
        CASE 
            WHEN rnk <= 3 THEN 'Top 3'
            WHEN rnk >= (SELECT MAX(rnk) FROM City_rnk_list) - 2 THEN 'Bottom 3'
            ELSE 'Others'
        END AS city_category
    FROM 
        City_rnk_list
)
SELECT 
    city_name, 
    new_passengers, 
    city_category
FROM 
    Categorized_Cities
WHERE 
    city_category IN ('Top 3', 'Bottom 3');

-- Business Request 5: Identify  Month with Highest Revenue for each city.

WITH monthly_revenue AS (
    SELECT 
        city.city_name AS city_name, 
        MONTHNAME(t.date) AS month_name, 
        SUM(t.fare_amount) AS Total_Revenue
    FROM 
        dim_city AS city
    JOIN 
        fact_trips AS t
        ON city.city_id = t.city_id
    GROUP BY 
        city.city_name, MONTHNAME(t.date)
),
ranked AS (
    SELECT 
        city_name, 
        month_name, 
        Total_Revenue,
        RANK() OVER (PARTITION BY city_name ORDER BY Total_Revenue DESC) AS rnk
    FROM 
        monthly_revenue
),
total_revenue_city AS (
    SELECT 
        city_name, 
        SUM(Total_Revenue) AS city_total_revenue
    FROM 
        monthly_revenue
    GROUP BY 
        city_name
)
SELECT 
    r.city_name, 
    r.month_name, 
    r.Total_Revenue AS revenue, 
    CONCAT(ROUND((r.Total_Revenue / t.city_total_revenue) * 100, 2), '%') AS Percentage_Contribution
FROM 
    ranked r
JOIN 
    total_revenue_city t 
    ON r.city_name = t.city_name
WHERE 
    r.rnk = 1;

        
-- Business Request 6: Repeat Passenger rate Analysis

-- Monthly Repeat Passenger Rate

select c.city_name, monthname(p.month) as month_name, p.total_passengers, p.repeat_passengers, 
concat(round((p.repeat_passengers/p.total_passengers)*100,2),'%') as Monthly_repeat_Passenger_rate
from  dim_city as c
join fact_passenger_summary as p
on c.city_id=p.city_id
order by month(p.month) ;

  -- City-wide Repeat Passenger Rate
  
select c.city_name, sum(p.total_passengers) as total_passenger, sum(p.repeat_passengers) as repeat_Passengers, 
concat(round((sum(p.repeat_passengers)/sum(p.total_passengers))*100,2),'%') as City_repeat_Passenger_rate
from  dim_city as c
join fact_passenger_summary as p
on c.city_id=p.city_id 
group by c.city_name;


