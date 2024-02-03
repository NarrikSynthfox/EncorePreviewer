local function rgb2num(red, green, blue)
	green = green * 256
	blue = blue * 256 * 256
	return red + green + blue
end

local r, g, b = 64,64,64
gfx.clear = rgb2num(r, g, b)

gfx.init("FNFest Preview", 640, 480, 0, 200, 200)

inst=1
diff=4
midihash=""
trackSpeed=2
pR={
	{{60,63},{66,69}},
	{{72,75},{78,81}},
	{{84,87},{90,93}},
	{{96,100},{102,106}}
}
oP=116
offset=0
diffNames={"Easy","Medium","Hard","Expert"}
notes={}
imgscale=math.min(gfx.w,gfx.h)/1024

local script_folder = string.gsub(debug.getinfo(1).source:match("@?(.*[\\|/])"),"\\","/")
hwy_emh = gfx.loadimg(0,script_folder.."assets/hwy_emh.png")
hwy_x = gfx.loadimg(1,script_folder.."assets/hwy_x.png")
note = gfx.loadimg(2,script_folder.."assets/note.png")
note_o = gfx.loadimg(3,script_folder.."assets/note_o.png")
lift = gfx.loadimg(4,script_folder.."assets/lift.png")
lift_o = gfx.loadimg(5,script_folder.."assets/lift_o.png")
lift_invalid = gfx.loadimg(6,script_folder.."assets/lift_invalid.png")

curBeat=0
curNote=1

nxs=152
nxm=0.05
nyoff=192
nsm=0.05
function getNoteIndex(time, lane)
    for i, note in ipairs(notes) do
        if note[1] == time and note[3] == lane then
            return i
        end
    end
    return -1
end

function findTrack(trackName)
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        local _, currentTrackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if currentTrackName == trackName then
            return track
        end
    end
    return nil
end

function parseNotes(take)
    notes = {}
	od_phrases={}
	od=false
	cur_od_phrase=1
    _, notecount = reaper.MIDI_CountEvts(take)

    for i = 0, notecount - 1 do
        _, _, _, spos, epos, _, pitch, _ = reaper.MIDI_GetNote(take, i)
        ntime = reaper.MIDI_GetProjQNFromPPQPos(take, spos)
        nend = reaper.MIDI_GetProjQNFromPPQPos(take, epos)

        if pitch == oP then
			table.insert(od_phrases, {ntime,nend})
        elseif pitch >= pR[diff][1][1] and pitch <= pR[diff][1][2] then
            lane = pitch - pR[diff][1][1]
			noteIndex = getNoteIndex(ntime, lane)
			if noteIndex ~= -1 then
                notes[noteIndex][2] = nend-ntime
            else
				table.insert(notes, { ntime, nend - ntime, lane, false, false })
            end
        elseif pitch >= pR[diff][2][1] and pitch <= pR[diff][2][2] then
            lane = pitch - pR[diff][2][1]
            noteIndex = getNoteIndex(ntime, lane)

            if noteIndex ~= -1 then
                notes[noteIndex][4] = true
            else
                table.insert(notes, { ntime, -1, lane, true, false })
            end
        end
    end
	if #od_phrases~=0 then
		for i=1,#notes do
			if notes[i][1]>od_phrases[cur_od_phrase][2] then
				if cur_od_phrase<#od_phrases then cur_od_phrase=cur_od_phrase+1 end
			end
			if notes[i][1]>=od_phrases[cur_od_phrase][1] and notes[i][1]<=od_phrases[cur_od_phrase][2] then
				notes[i][5]=true
			end
		end
	end
end


instrumentTracks={
	{"Drums",findTrack("PART DRUMS")},
	{"Bass",findTrack("PART BASS")},
	{"Guitar",findTrack("PART GUITAR")},
	{"Vocals",findTrack("PART VOCALS")}
}

eventTracks={
	findTrack("EVENTS"),
	findTrack("BEAT")
}

function updateMidi()
	instrumentTracks={
		{"Drums",findTrack("PART DRUMS")},
		{"Bass",findTrack("PART BASS")},
		{"Guitar",findTrack("PART GUITAR")},
		{"Vocals",findTrack("PART VOCALS")}
	}
	if instrumentTracks[inst][2] then
		local numItems = reaper.CountTrackMediaItems(instrumentTracks[inst][2])
		for i = 0, numItems-1 do
			local item = reaper.GetTrackMediaItem(instrumentTracks[inst][2], i)
			local take = reaper.GetActiveTake(item)
			local _,hash=reaper.MIDI_GetHash(take,true)
			if midihash~=hash then
				parseNotes(take)
				curNote=1
				for i=1,#notes do
					curNote=i
					if notes[i][1]+notes[i][2]>=curBeat then
						break
					end
					
				end
				midihash=hash
			end
		end
	else
		midihash=""
		notes={}
	end
end

function drawNotes()
	for i=curNote,#notes do
		invalidLift=false
		ntime=notes[i][1]
		nlen=notes[i][2]
		if nlen==-1 then
			invalidLift=true
		end
		lane=notes[i][3]
		lift=notes[i][4]
		curend=((notes[curNote][1]+notes[curNote][2])-curBeat)*trackSpeed
		od=notes[i][5]
		if ntime>curBeat+(4/trackSpeed) then break end
		rtime=((ntime-curBeat)*trackSpeed)+offset
		rend=(((ntime+nlen)-curBeat)*trackSpeed)+offset
		if rtime<0 then rtime=0 end
		if nlen<=0.27 then
			rend=rtime
		end
		
		if rend<=0 and curnote~=#notes and curend<=0 then
			curNote=i+1
		end
		if rend>4 then
			rend=4
		end
		
		notescale=imgscale*(1-(nsm*rtime))
		notescaleend=imgscale*(1-(nsm*rend))
		if diff<4 then
			lane=lane+0.5
		end
		notex=((gfx.w/2)-(64*notescale)+((nxs*(1-(nxm*rtime)))*notescale*(lane-2)))
		notey=gfx.h-(32*notescale)-(248*notescale)-((nyoff*rtime)*notescale)
		susx=((gfx.w/2)+((nxs*(1-(nxm*rtime)))*notescale*(lane-2)))
		susy=gfx.h-(248*notescale)-((nyoff*rtime)*notescale)
		endx=((gfx.w/2)+((nxs*(1-(nxm*rend)))*notescaleend*(lane-2)))
		endy=gfx.h-(248*notescaleend)-((nyoff*rend)*notescaleend)
		gfxid=2
		if lift then gfxid=4 end
		if od then 
			gfxid=gfxid+1 
			gfx.r, gfx.g, gfx.b=1,.56,0
		else
			gfx.r, gfx.g, gfx.b=0.72,.3,1
		end
		if rend>rtime then
			gfx.line(susx-1,susy,endx-1,endy)
			gfx.line(susx,susy,endx,endy)
			gfx.line(susx+1,susy,endx+1,endy)
		end
		if invalidLift then gfxid=6 end
		gfx.r, gfx.g, gfx.b=1,1,1
		gfx.blit(gfxid,notescale,0,0,0,128,64,notex,notey)
		
	end
end
lastCursorTime=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetCursorPosition())
updateMidi()
local function Main()
	
	imgscale=math.min(gfx.w,gfx.h)/1024
	local char = gfx.getchar()
	if char ~= -1 then
		reaper.defer(Main)
	end
	if char == 59 then -- [
		if diff==1 then diff=4 else diff=diff-1 end
		midihash=""
		updateMidi()
	elseif char == 39 then -- ]
		if diff==4 then diff=1 else diff=diff+1 end
		midihash=""
		updateMidi()
	elseif char == 91 then -- ;
		if inst==1 then inst=4 else inst=inst-1 end
		midihash=""
		updateMidi()
	elseif char == 93 then -- '
		if inst==4 then inst=1 else inst=inst+1 end
		midihash=""
		updateMidi()
	elseif char == 43 then -- +
		trackSpeed = trackSpeed+0.05
	elseif char == 45 then -- -
		if trackSpeed>0.25 then trackSpeed = trackSpeed-0.05 end
	elseif char == 125 then -- {
		offset = offset+0.01
	elseif char == 123 then -- - }
		offset = offset-0.01
	end

	-- if char~=0 then
	-- 	reaper.ShowConsoleMsg(tostring(char).."\n")
	-- end
	gfx.setfont(1, "Arial", 16)
	
	if diff==4 then
		gfx.blit(1,imgscale,0,0,0,1024,1024,(gfx.w/2)-(imgscale*512),gfx.h-(1024*imgscale)); 
	else
		gfx.blit(0,imgscale,0,0,0,1024,1024,(gfx.w/2)-(imgscale*512),gfx.h-(1024*imgscale));   
	end 
	playState=reaper.GetPlayState()
	if playState==1 then
		curBeat=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetPlayPosition())
	end
	curCursorTime=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetCursorPosition())
	if playState~=1 then
		curBeat=curCursorTime
	end
	if curCursorTime~=lastCursorTime then
		lastCursorTime=curCursorTime
		curNote=1
		for i=1,#notes do
			curNote=i
			if notes[i][1]+notes[i][2]>=curBeat then
				break
			end
			
		end
	end
	gfx.x,gfx.y=0,0
	gfx.drawstr(string.format(
		[[Instrument: %s, change with [ / ]
		Difficulty: %s, change with ; / '
		Track Speed: %.02f, change with + / -
		Offset: %.02f, change with { / }
		Note Count: %d
		Current Beat: %.02f
		Current Note: %d
		]],
		instrumentTracks[inst][1],
		diffNames[diff],
		trackSpeed,
		offset,
		tostring(#notes),
		curBeat,
		curNote
	))
	updateMidi()
	drawNotes()
	gfx.update()
end

Main()