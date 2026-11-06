-- ========================================================================
-- 1. Calculate total RNs, revenue, and ADR by city for each month in 2024
-- ========================================================================
with monthly_data as (
	select 
		pt."CITY" as city
		, date_part('month', bt."CHECK_OUT_DATE") as month
		, sum(bt."ROOM_NIGHTS") as total_rns
		, sum(bt."REVENUE_DOLLAR") as total_revenue
	from 
		bookings_table bt 
	left join
		property_table pt on bt."PROPERTY_CODE" = pt."PROPERTY_CODE"
	where 
		date_part('year', bt."CHECK_OUT_DATE") = 2024
	group by
		city, month
)

select 
	city
	, month
	, total_rns
	, total_revenue
	, round(total_revenue::numeric / total_rns, 2) as  adr
from 
	monthly_data
order by
	city, month;



-- ========================================================================================
-- 2. Identify the top 10 properties in terms of RNs growth comparing YTD 2023 to YTD 2024
-- ========================================================================================
with ytd_data as (
	select 
		"PROPERTY_CODE" as property_code
		, date_part('year', "CHECK_IN_DATE") as year
		, sum("ROOM_NIGHTS") as total_rns
	from
		bookings_table 
	where 
		(date_part('year', "CHECK_IN_DATE") = 2023 and "CHECK_IN_DATE" <= '2023-11-30') or 
		(date_part('year', "CHECK_IN_DATE") = 2024 and "CHECK_IN_DATE" <= '2024-11-30')
	group by 
		property_code, year
),
rns_growth as (
	select 
		a.property_code
		, a.total_rns as rns_2023
		, b.total_rns as rns_2024
		, round(((b.total_rns - a.total_rns)::numeric / a.total_rns) * 100, 2) as growth_percentage
	from 
		(select * from ytd_data where year=2023) a
	left join 
		(select * from ytd_data where year=2024) b on a.property_code = b.property_code	
)

select 
	rg.property_code
	, rg.rns_2023
	, rg.rns_2024
	, rg.growth_percentage
	, pt."CITY"
	, pt."BRAND_TYPE"
from 
	rns_growth rg
left join
	property_table pt 
	on rg.property_code = pt."PROPERTY_CODE"
order by
	growth_percentage desc 
limit 10;



-- ================================================================
-- 3. Determine customer segmentation based on purchasing behavior
-- ================================================================
with customer_behavior as (
	select 
		ut."USER_ID" as user_id
		, count(distinct bt."BOOKING_ID") as total_bookings
		, sum(bt."REVENUE_DOLLAR") as total_spent
		, round(avg(bt."REVENUE_DOLLAR")::numeric, 2) as avg_booking_spent
	from 
		user_table ut 
	left join
		bookings_table bt on ut."USER_ID" = bt."USER_ID"
	group by
		ut."USER_ID"
),
global_average as (
	select 
		avg(total_bookings) as avg_total_booking
		, avg(avg_booking_spent) as avg_avg_booking_spent
	from
		customer_behavior
),
customer_segmentation as (
	select
		cb.user_id
		, cb.total_bookings
		, cb.total_spent
		, cb.avg_booking_spent
		, case 
			when cb.total_bookings > ga.avg_total_booking then 'High Booking Frequency'
			else 'Low Booking Frequency'
		end as booking_frequency_segment
		, case 
			when cb.avg_booking_spent > ga.avg_avg_booking_spent then 'High Spending'
			else 'Low Spending'
		end as spending_segment	
	from 
		customer_behavior cb
	cross join
		global_average ga
)

select 
	*
from 
	customer_segmentation



-- ==================================================================
-- 4. Compare normal season vs. peak season pricing in 2023 and 2024
-- ==================================================================
with property_monthly_booking as (
	select 
		date_part('year', bt."CHECK_IN_DATE") as year
		, date_part('month', bt."CHECK_IN_DATE") as month
		, sum(bt."REVENUE_DOLLAR") as total_revenue
		, sum(bt."ROOM_NIGHTS") as total_rns
	from 
		bookings_table bt 
	where 
		date_part('year', bt."CHECK_IN_DATE") in (2023, 2024)
	group by 
		year, month 
	order by 
		year, month		
)
select 
	year
	, case 
		when month in (6, 7) then 'peak season'
		else 'normal season'
	end as season
	, sum(total_revenue)/sum(total_rns) as adr
from 
	property_monthly_booking
group by
	year, season
order by 
	year, season;


	
-- ======================================================================
-- 5. Analyze the quality of acquired properties using logic-based grade
-- ======================================================================
with property_monthly_booking as (
	select 
		pt."PROPERTY_CODE" as property_code
		, pt."INVENTORY" as inventory
		, sum(bt."ROOM_NIGHTS") as total_rns
		, date_part('year', bt."CHECK_IN_DATE") as year
		, date_part('month', bt."CHECK_IN_DATE") as month
		, extract(day from (date_trunc('month', min(bt."CHECK_IN_DATE")) + interval '1 MONTH' - interval '1 day')) AS days_in_month
	from 
		property_table pt 
	join
		bookings_table bt on pt."PROPERTY_CODE" = bt."PROPERTY_CODE"
	group by 
		pt."PROPERTY_CODE", year, month , pt."INVENTORY"
	order by 
		pt."PROPERTY_CODE", year, month		
),
property_monthly_summary as (
	select 
		property_code
		, month 
		, sum(days_in_month) as days_active
		, inventory
		, sum(total_rns) as total_rns
	from 
		property_monthly_booking
	group by
		property_code, month, inventory
	order by 
		property_code, month 
),
property_monthly_occupancy_rate as (
	select 
		property_code
		, month
		, (total_rns / (days_active*inventory)) as occupancy_rate
	from 
		property_monthly_summary
),
average_monthly_occupancy as (
	select 
		property_code
		, round(avg(occupancy_rate)*100, 2) as monthly_occupancy_percentage	
	from 
		property_monthly_occupancy_rate
	group by
		property_code
)

select 
	property_code
	, monthly_occupancy_percentage	
	, case 
		when monthly_occupancy_percentage > 80 then 'A'
		when monthly_occupancy_percentage between 70 and 80 then 'B'
		when monthly_occupancy_percentage between 40 and 69 then 'C'
		when monthly_occupancy_percentage between 20 and 39 then 'D'
		when monthly_occupancy_percentage < 20 then 'E'
	end as grade
from 
	average_monthly_occupancy 
order by
	monthly_occupancy_percentage desc;



-- =============================================================================
-- 6. Create SQL View for regular reporting (last 6 months key metrics by city)
-- =============================================================================
create or replace view city_performance as
with recent_bookings as (
	select
		pt."CITY" as city 
		, sum(bt."ROOM_NIGHTS") as total_rns
		, sum(bt."REVENUE_DOLLAR") as total_revenue
		, date_trunc('month', bt."CHECK_IN_DATE") as booking_month
	from 
		bookings_table bt 
	left join
		property_table pt 
		on bt."PROPERTY_CODE" = pt."PROPERTY_CODE"
	where 	
		bt."CHECK_IN_DATE" >= date_trunc('months', current_date) - interval '6 months'
	group by 
		city, booking_month
),
city_inventory as (
	select 
		pt."CITY" as city
		, sum(pt."INVENTORY") as total_inventory
	from 
		property_table pt 
	group by
		city
),
city_performance_data as (
	select 
		rb.city as city
		, ci.total_inventory as total_inventory
		, sum(rb.total_revenue) as total_revenue
		, sum(rb.total_rns) as total_rns
		, sum(extract(day from (date_trunc('months', rb.booking_month) + interval '1 month' - interval '1 day'))) as days_active
	from 
		recent_bookings rb
	left join
		city_inventory ci
		on rb.city = ci.city
	group by 
		rb.city, total_inventory
)

select 
	cpd.city
	, cpd.total_revenue 
	, round((cpd.total_rns / (cpd.total_inventory * cpd.days_active)) * 100, 2) AS occupancy_rate
	, round(cpd.total_revenue::numeric / cpd.total_rns, 2) AS adr
    , round(cpd.total_revenue::numeric / (cpd.total_inventory * cpd.days_active), 2) AS revpar
from 
	city_performance_data cpd 
	