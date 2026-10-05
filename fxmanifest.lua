fx_version "cerulean"
game "gta5"

title "Rent Vehicle"
description "Rent Vehicle"
author "OldMoney"

shared_scripts {
    "@es_extended/imports.lua",
    "shared/config.lua"
}

client_scripts {
    "client/main.lua"
}

server_scripts {
    "server/main.lua"
}

file "ui/dist/**/*"

ui_page "ui/dist/index.html"
