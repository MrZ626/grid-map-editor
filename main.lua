require'Zenitha'

ZENITHA.globalEvent.drawCursor=NULL
ZENITHA.globalEvent.clickFX=NULL

SCN.add('editor',require'editor')
ZENITHA.setFirstScene('editor')
ZENITHA.setRenderRate(50)
