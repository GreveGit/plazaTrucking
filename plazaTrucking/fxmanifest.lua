fx_version 'cerulean'
game 'gta5'
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua'
    'config.lua',
}

client_scripts {
    'bridge/client/**.lua',
    'cl_trucking.lua'
}

server_scripts {
    'bridge/server/**.lua',
    'sv_config.lua',
    'sv_trucking.lua',
}

