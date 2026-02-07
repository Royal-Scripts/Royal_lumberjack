server_script '@Wolf-Block-Backdoor/firewall.lua'
server_script '@Wolf-Block-Backdoor/firewall.js'
fx_version 'cerulean'
game 'gta5'

author 'Qbox Developer'
description 'Royal Lumberjack Job (No Crafting Version)'
version '1.5.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/sound/pedvoice.mp3',
    'html/sound/woodcut.mp3',
    'html/sound/woodfall.mp3'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql'
}