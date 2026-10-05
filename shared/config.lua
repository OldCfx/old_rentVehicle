Config = {}

Config.AppLabel = "Location Véhicule"                       -- Nom de l'application affiché dans le téléphone
Config.AppIcon =
"https://cfx-nui-old_rentVehicle/ui/dist/icon.svg"          -- URL de l'icône de l'application affichée dans le téléphone
Config.DefaultApp = false                                   -- Si l'application est installée par défaut dans le téléphone du joueur

Config.MinSpawnDistance = 60.0                              -- Distance minimale entre le joueur et le point de spawn du véhicule
Config.MaxSpawnDistance = 140.0                             -- Distance maximale entre le joueur et le point de spawn du véhicule
Config.DriverPedModel =
"s_m_m_autoshop_01"                                         -- Modèle du PNJ qui sera généré pour remettre le véhicule au joueur

Config.Fleet = {                                            -- Liste des véhicules disponibles à la location
    club = {                                                -- nom de spawn
        name = "Club",                                      -- label du véhicule
        seats = 2,                                          -- nombre de places
        pricePer15 = 120,                                   -- prix pour 15 minutes
        image =
        "https://docs-backend.fivem.net/vehicles/club.webp" -- URL de l'image du véhicule affichée dans l'application
    },
    sultan = {
        name = "Sultan",
        seats = 4,
        pricePer15 = 150,
        image = "https://docs-backend.fivem.net/vehicles/sultan.webp"
    },
    kamacho = {
        name = "Kamacho",
        seats = 4,
        pricePer15 = 220,
        image = "https://docs-backend.fivem.net/vehicles/kamacho.webp"
    },
    drafter = {
        name = "8F Drafter",
        seats = 2,
        pricePer15 = 350,
        image = "https://docs-backend.fivem.net/vehicles/drafter.webp"
    }
}

Config.Durations = { -- Liste des durées de location disponibles
    { id = "4m",  label = "4 min",    minutes = 4,   mult = 1.0 },
    { id = "30m", label = "30 min",   minutes = 30,  mult = 1.8 },
    { id = "1h",  label = "1 heure",  minutes = 60,  mult = 3.2 },
    { id = "2h",  label = "2 heures", minutes = 120, mult = 5.5 }
}
