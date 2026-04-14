# Uptime-Critical
A 2d survival game about running a data center

## To Play Game
1) Download Uptime-Critical.exe
2) Run it

## Balance Pass 1 Targets

The current economy pass is tuned around medium early-game pacing and healthier daisy chaining.

| Item | Target |
| --- | --- |
| Server Rack L1 capacity | 270 req/s |
| Server Rack L2 capacity | 390 req/s |
| Server Rack L3 capacity | 540 req/s |
| Cat5 capacity | 900 req/s |
| Cat6 capacity | 1800 req/s |
| Fiber capacity | 3600 req/s |
| Internet Pipe capacity | 9000 req/s |
| Power Cable capacity | 1800 req/s |

Rule of thumb: a cable should carry at least 3 lower-tier servers before it becomes the bottleneck, with higher tiers scaling to 4 to 6 lower-tier loads. That keeps daisy chaining useful without making the first cable effectively a hard cap.

## Traffic Model Notes

Traffic is now tuned to be high and dynamic from the start, and it scales with current datacenter capacity:

| Knob (GameManager) | Intent |
| --- | --- |
| `starting_load_ratio` | Higher initial traffic at session start |
| `baseline_demand_capacity_ratio` | Baseline demand relative to available capacity |
| `demand_capacity_follow_speed` | How quickly market demand follows capacity changes |
| `traffic_growth_rate` | Organic demand growth rate (capacity-scaled) |
| `traffic_floor_ratio` / `traffic_peak_ratio` | Day/night load range |
| `traffic_volatility_ratio` | Amplitude of short-term fluctuation |
| `traffic_volatility_change_speed` | How quickly fluctuation changes |
| `traffic_response_speed` | How quickly live load responds to target demand |
| `traffic_ramp_minutes_to_max` | Real-time minutes for traffic pressure to reach max ramp |
| `traffic_ramp_multiplier_max` | Long-session demand multiplier ceiling |
| `traffic_ramp_curve_exponent` | Ramp curve shape (higher = later acceleration) |
| `traffic_overload_ceiling_ratio` | Max incoming valid traffic vs current datacenter capacity |

These four ramp controls are now centralized in `EconomyConfig` for balancing consistency.

Design goal: incoming traffic should be visibly noisy and substantial from the beginning, while still respecting current available bandwidth so upgrades directly increase practical traffic throughput.

### Adam Lind Quote
"The only thing necessary for the triumph of evil is for good men to do nothing." -- Unknown

### Keith Eberhard Quote
"perfection is achieved not when there is nothing more to add, but when there is nothing left to take away" - Antoine de Saint-Exupéry

### Zach Sutherland Quote
“Anything that can go wrong will go wrong.” - Murphy's Law

### Micaela Morales Quote
"There is nothing like dogma to produce a dream, and nothing like a dream to create the future." - Victor Hugo (Les Miserables)
