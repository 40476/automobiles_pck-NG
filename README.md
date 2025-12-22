# Automobiles NG

[![automobiles](https://user-images.githubusercontent.com/95320171/198845469-fe7bbe2d-19e9-42da-8343-9c32c1cdbd0b.png)](https://content.minetest.net/packages/apercy/automobiles_pck/)

Modpack to add automobiles to Minetest. The main goal of this modpack is realistic driving over slopes and elevations.
Fuel is needed to operate the vehicles, however a small amount of fuel is provided in each vehicle on creation.

## Dependencies

- [biofuel](https://content.minetest.net/packages/Lokrates/biofuel/)
- player_api

## Vehicle Operation
`W`: Forward

`S`: Brake

`A`: Left

`D`: Right

`E`: Horn

`Shift`: Reverse

Vehicles can be colored by punching them with either dye or the vehicle painter. To fuel a vehicle, punch it with biofuel.

## Key Features

### Physics & Mechanics

- Realistic terrain navigation including slopes and elevation changes  
- Buoyancy system for water interactions  
- Ground friction and suspension physics  
- Disability in liquid when buoyancy > 1  

### Vehicle Customization

- Paint customization with dyes/vehicle painter
- Horn sound activation
- Springiness/bounce physics customization
- Custom license plates with alphanumeric validation
  - 2-8 character format support
  - Automatic uppercase conversion
  - Dynamic texture generation

### Core Systems

- Fuel requirement with initial starter supply  
- Reverse gear capabilities  
- Wheel animations tied to movement  
- Automatic engine cutoff when stationary  
- Water drag mechanics  

### Vehicle Variety

- Multiple vehicle types included (Beetle, Buggy, Coupe, etc.)  
- Unique handling characteristics per vehicle  

### Autonomous Features

- Waypoint navigation system with pathfinding  
- Automatic obstacle detection and avoidance  
- Speed adaptation based on terrain clearance  
- PID-controlled steering system  
- Automatic braking when approaching obstacles  
- Path recalculation capability  
- Driver notifications via chat
