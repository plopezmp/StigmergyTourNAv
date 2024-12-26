# Stigmergy-Based Tourist Navigation System
This repository contains the materials used in the study 

Pablo López-Matencio, Javier Vales-Alonso, and Enrique Costa-Montenegro, “ANT: Agent Stigmergy-Based IoT-Network for Enhanced Tourist Mobility,” *Mobile Information Systems*, vol. 2017, Article ID 1328127, 15 pages, 2017. https://doi.org/10.1155/2017/1328127

The goal of this work is to study stigmergy as a way to collectively help tourists to discover points of interests, POIs, and find routes to those sites.
Stigmergy is the type of communication used used by some spieces of insects, e.g. ants, for foraging purposes. The insect liberates chemicals denominated *pheromones* that other individuals can sense. Stigmergy can be applied  to solve complex problems in real world scenarios, such as tourist routing.


## Operation overview

<br><br>
<div align="center" style="margin-top: 0.7cm; margin-bottom: 20px;">
  <img src="figs/PLMado.png" width="750">
  <p><b>Figure 1:</b> System overview.</p>
</div>
<br><br>

Pheromone mapping determines a tourist's route based on different strategies with the following rules:

1. **Without pheromone**, a tourist chooses their path freely, with no influence from other agents.
2. **ANT software** tracks the tourist's path for a set **Memory Path Interval (MPI)**.
3. When a tourist stays at a location during a **POI Detection Interval (POI-DI)**, the system declares it a POI and sends the **Route Information (RI)** to the server, considering **POI Area Distance (POI-AD)** to trigger the POI.
4. The server checks if the POI is new by comparing it with nearby declared POIs. If new, a **POI Unique Number (POI-UN)** is created. The server adds pheromone to the RI based on route ranking.
5. Every **Updating Period (UP)**, the server evaporates pheromone at a predefined rate. If a POI's pheromone disappears, its information is removed.
6. The server provides tourists with an **Individualized Pheromone Mapping (IPM)**, which is unique to each tourist and guides them towards unvisited POIs.
7. The **ANT agent** uses the IPM to select routes, often leading to popular unvisited POIs.
8. The system also records and submits path data during special events, allowing new POIs to be declared for temporary locations.
