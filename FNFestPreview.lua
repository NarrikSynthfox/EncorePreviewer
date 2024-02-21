version_num="0.0.7"
imgScale=480/1024
diffNames={"Easy","Medium","Hard","Expert"}
movequant=10
quants={1/32,1/24,1/16,1/12,1/8,1/6,1/4,1/3,1/2,1,2,4}
--highway rendering vars
midiHash=""
beatHash=""
eventsHash=""
trackSpeed=2
inst=1
diff=4
pR={
	{{60,63},{66,69}},
	{{72,75},{78,81}},
	{{84,87},{90,93}},
	{{96,100},{102,106}}
} --pitch ranges {{notes},{lift markers}} for each difficulty
oP=116 --overdrive pitch
offset=0
notes={}
beatLines={}
eventsData={}
trackRange={0,0}
curBeat=0
curBeatLine=1
curEvent=1
curNote=1
nxoff=152 --x offset
nxm=0.05 --x mult of offset
nyoff=192 --y offset
nsm=0.05 --scale multiplier

lastCursorTime=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetCursorPosition())

showHelp=false

local function rgb2num(r, g, b)
	g = g * 256
	b = b * 256 * 256
	return r + g + b
end

function toFractionString(number)
	if number<1 then
		return string.format('1/%d', math.floor(1/number))
	else
		return string.format('%d',number)
	end
end

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

gfx.clear = rgb2num(42, 0, 71)
gfx.init("FNFest Preview", 640, 480, 0, 200, 200)




local script_folder = string.gsub(debug.getinfo(1).source:match("@?(.*[\\|/])"),"\\","/")
hwy_emh = gfx.loadimg(0,script_folder.."assets/hwy_emh.png")
hwy_x = gfx.loadimg(1,script_folder.."assets/hwy_x.png")
note = gfx.loadimg(2,script_folder.."assets/note.png")
note_o = gfx.loadimg(3,script_folder.."assets/note_o.png")
note_invalid = gfx.loadimg(7,script_folder.."assets/note_invalid.png")
lift = gfx.loadimg(4,script_folder.."assets/lift.png")
lift_o = gfx.loadimg(5,script_folder.."assets/lift_o.png")
lift_invalid = gfx.loadimg(6,script_folder.."assets/lift_invalid.png")

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
local function notesCompare(a, b)
    if a[1] < b[1] then
        return true
    elseif a[1] > b[1] then
        return false
    else
        return a[3] < b[3]
    end
end
local function notesCompareFlip(a, b)
    if a[1] < b[1] then
        return true
    elseif a[1] > b[1] then
        return false
    else
        return a[3] > b[3]
    end
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
			valid=true
			lane = pitch - pR[diff][1][1]
			noteIndex = getNoteIndex(ntime, lane)
			if noteIndex ~= -1 then
				if nend-ntime<0.33 and notes[noteIndex][2]==nend-ntime then
					notes[noteIndex][6] = valid
				end
			else
				table.insert(notes, { ntime, nend - ntime, lane, false, false, valid })
			end
		elseif pitch >= pR[diff][2][1] and pitch <= pR[diff][2][2] then
			lane = pitch - pR[diff][2][1]
			noteIndex = getNoteIndex(ntime, lane)
			if noteIndex ~= -1 then
				notes[noteIndex][4] = true
				if nend-ntime>0.33 or notes[noteIndex][2]~=nend-ntime then
					notes[noteIndex][6] = false
				end
			else
				table.insert(notes, { ntime, nend - ntime, lane, true, false, false })
			end
		end
	end
	if #od_phrases~=0 then
		for i=1,#notes do
			if notes[i][1]>od_phrases[cur_od_phrase][2] then
				if cur_od_phrase<#od_phrases then cur_od_phrase=cur_od_phrase+1 end
			end
			if notes[i][1]>=od_phrases[cur_od_phrase][1] and notes[i][1]<od_phrases[cur_od_phrase][2] then
				notes[i][5]=true
			end
		end
	end
	table.sort(notes,notesCompare)
	--illegal chords check
	for i=1,#notes do
		ntime=notes[i][1]
		lane=notes[i][3]
		if lane==0 or lane==1 then
			for f = 0,1 do
				invalidIndex = getNoteIndex(ntime, f)
				if invalidIndex~=-1 and f~=lane then
					notes[i][6]=false
					notes[invalidIndex][6]=false
				end
			end
		elseif lane==2 or lane==3 or lane==4 then
			for f = 2,4 do
				invalidIndex = getNoteIndex(ntime, f)
				if invalidIndex~=-1 and f~=lane then
					notes[i][6]=false
					notes[invalidIndex][6]=false
				end
			end
		end
	end
	--extended sustain check
	sustain=false
	sustain_idx=-1
	sustain_start=-1
	sustain_end=-1
	for i=1,#notes do
		ntime=notes[i][1]
		if ntime>=sustain_end then 
			sustain=false
			sustain_idx=-1
			sustain_start=-1
			sustain_end=-1
		end
		nlen=notes[i][2]
		nend=ntime+notes[i][2]
		lane=notes[i][3]
		if sustain==true then
			if ntime<sustain_end then
				if ntime~=sustain_start or nend~=sustain_end then
					notes[i][6]=false
					notes[sustain_idx][6]=false
				end
			end
		else
			if nlen>=0.33 then
				sustain=true
				sustain_start=ntime
				sustain_end=nend
				sustain_idx=i
			end
		end
	end
	table.sort(notes,notesCompareFlip)
	for i=1,#notes do
		ntime=notes[i][1]
		if ntime>=sustain_end then 
			sustain=false
			sustain_idx=-1
			sustain_start=-1
			sustain_end=-1
		end
		nlen=notes[i][2]
		nend=ntime+notes[i][2]
		lane=notes[i][3]
		if sustain==true then
			if ntime<sustain_end then
				if ntime~=sustain_start or nend~=sustain_end then
					notes[i][6]=false
					notes[sustain_idx][6]=false
				end
			end
		else
			if nlen>=0.33 then
				sustain=true
				sustain_start=ntime
				sustain_end=nend
				sustain_idx=i
			end
		end
	end
	--set all notes at time to invalid if one is
	for i=1,#notes do
		ntime=notes[i][1]
		lane=notes[i][3]
		for f = 0,4 do
			invalidIndex = getNoteIndex(ntime, f)
			if invalidIndex~=-1 then
				if notes[invalidIndex][6]==false then notes[i][6]=false end
			end
		end
	end
	
end

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
			if midiHash~=hash then
				parseNotes(take)
				curNote=1
				for i=1,#notes do
					curNote=i
					if notes[i][1]+notes[i][2]>=curBeat then
						break
					end
					
				end
				midiHash=hash
			end
		end
	else
		midiHash=""
		notes={}
	end
end

function updateEvents()
	eventTracks[1]=findTrack("EVENTS")
	if eventTracks[1] then
		local numItems = reaper.CountTrackMediaItems(eventTracks[1])
		for i = 0, numItems-1 do
			local item = reaper.GetTrackMediaItem(eventTracks[1], i)
			local take = reaper.GetActiveTake(item)
			local _,hash=reaper.MIDI_GetHash(take,false)
			if eventsHash~=hash then
				eventsData={}
				_,_,_,textcount = reaper.MIDI_CountEvts(take)
				for i = 0, textcount - 1 do
					_,_,_,epos,etype,msg = reaper.MIDI_GetTextSysexEvt(take, i)
					etime = reaper.MIDI_GetProjQNFromPPQPos(take, epos)
					if etype==1 then
						table.insert(eventsData,{epos,msg})
						if msg=="[music_start]" then trackRange[1]=etime
						elseif msg=="[end]" then trackRange[2]=etime
						end
					end
				end
				eventsHash=hash
			end
		end
	else
		eventsHash=""
		eventsData={}
	end
end

function updateBeatLines()
	eventTracks[2]=findTrack("BEAT")
	if eventTracks[2] then
		local numItems = reaper.CountTrackMediaItems(eventTracks[2])
		for i = 0, numItems-1 do
			local item = reaper.GetTrackMediaItem(eventTracks[2], i)
			local take = reaper.GetActiveTake(item)
			local _,hash=reaper.MIDI_GetHash(take,true)
			if beatHash~=hash then
				beatLines={}
				_, notecount = reaper.MIDI_CountEvts(take)
				for i = 0, notecount - 1 do
					_, _, _, spos, _, _, pitch, _ = reaper.MIDI_GetNote(take, i)
					btime = reaper.MIDI_GetProjQNFromPPQPos(take, spos)
					db=true
					if pitch==13 then
						db=false
					end
					if btime>=trackRange[1] and btime<trackRange[2] then
						table.insert(beatLines,{btime,db})
					end
				end
				beatHash=hash
			end
		end
	else
		beatHash=""
		beatLines={}
	end
end

function drawNotes()
	for i=curNote,#notes do
		invalid=false
		ntime=notes[i][1]
		nlen=notes[i][2]
		if notes[i][6]==false then
			invalid=true
		end
		lane=notes[i][3]
		lift=notes[i][4]
		curend=((notes[curNote][1]+notes[curNote][2])-curBeat)*trackSpeed
		od=notes[i][5]
		if ntime>curBeat+(4/trackSpeed) then break end
		rtime=((ntime-curBeat)*trackSpeed)
		rend=(((ntime+nlen)-curBeat)*trackSpeed)
		if nlen<=0.27 then
			rend=rtime
		end
		
		if rtime<0 then rtime=0 end
		
		if rend<=0 and curNote~=#notes and curend<=0 then
			curNote=i+1
		end

		if rend>4 then
			rend=4
		end
		
		noteScale=imgScale*(1-(nsm*rtime))
		noteScaleEnd=imgScale*(1-(nsm*rend))
		if diff<4 then
			lane=lane+0.5
		end
		notex=((gfx.w/2)-(64*noteScale)+((nxoff*(1-(nxm*rtime)))*noteScale*(lane-2)))
		notey=gfx.h-(32*noteScale)-(248*noteScale)-((nyoff*rtime)*noteScale)
		susx=((gfx.w/2)+((nxoff*(1-(nxm*rtime)))*noteScale*(lane-2)))
		susy=gfx.h-(248*noteScale)-((nyoff*rtime)*noteScale)
		endx=((gfx.w/2)+((nxoff*(1-(nxm*rend)))*noteScaleEnd*(lane-2)))
		endy=gfx.h-(248*noteScaleEnd)-((nyoff*rend)*noteScaleEnd)
		
		if rend>=-0.05 then
			gfxid=2
			if lift then gfxid=4 end 
			if od then 
				gfxid=gfxid+1 
				gfx.r, gfx.g, gfx.b=1,.56,0
			else
				gfx.r, gfx.g, gfx.b=0.72,.3,1
			end
			if invalid then
				gfx.r, gfx.g, gfx.b=1,0,0
			end
			if rend>rtime then
				gfx.line(susx-1,susy,endx-1,endy)
				gfx.line(susx,susy,endx,endy)
				gfx.line(susx+1,susy,endx+1,endy)
			end
			if invalid and lift then gfxid=6 end
			if invalid and not lift then gfxid=7 end
			gfx.r, gfx.g, gfx.b=1,1,1
			gfx.blit(gfxid,noteScale,0,0,0,128,64,notex,notey)
		end
	end
end

function drawBeats()
	width=300
	if diff==4 then
		width=425
	end
	for i=curBeatLine,#beatLines do
		btime=beatLines[i][1]
		if btime>curBeat+(4/trackSpeed) then break end
		if curBeat>btime+2 then
			curBeatLine=i
		end
		rtime=((btime-curBeat)*trackSpeed)-0.08
		beatScale=imgScale*(1-(nsm*rtime))
		
		sx=((gfx.w/2)-((width*(1-(nxm*rtime)))*beatScale))
		ex=((gfx.w/2)+((width*(1-(nxm*rtime)))*beatScale))
		y=gfx.h-(248*beatScale)-((nyoff*rtime)*beatScale)
		gfx.line(sx,y,ex,y)
		if beatLines[i][2] then
			gfx.line(sx+1,y-1,ex-1,y-1)
			gfx.line(sx-1,y+1,ex+1,y+1)
		end
	end
end

updateMidi()
updateEvents()
updateBeatLines()

function moveCursorByBeats(increment)
    local currentPosition = reaper.GetCursorPosition()
    local currentBeats = reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1), currentPosition)

    -- Calculate the new position in beats
	local newBeats = currentBeats + increment
	newBeats=math.floor(newBeats*(1/quants[movequant])+0.5)/(1/quants[movequant])
	-- Convert the new beats position to seconds
    local newPosition = reaper.TimeMap2_QNToTime(reaper.EnumProjects(-1), newBeats)
    -- Move the edit cursor to the new position
    reaper.SetEditCurPos2(0, newPosition, true, true)
end

keyBinds={
	[59]=function()
		if diff==1 then diff=4 else diff=diff-1 end
		midiHash=""
		updateMidi()
	end,
	[39]=function()
		if diff==4 then diff=1 else diff=diff+1 end
		midiHash=""
		updateMidi()
	end,
	[91]=function()
		if inst==1 then inst=4 else inst=inst-1 end
		midiHash=""
		updateMidi()
	end,
	[93]=function()
		if inst==4 then inst=1 else inst=inst+1 end
		midiHash=""
		updateMidi()
	end,
	[43]=function()
		trackSpeed = trackSpeed+0.05
	end,
	[61]=function()
		trackSpeed = trackSpeed+0.05
	end,
	[45]=function()
		if trackSpeed>0.25 then trackSpeed = trackSpeed-0.05 end
	end,
	[125]=function()
		offset = offset+0.01
	end,
	[123]=function()
		offset = offset-0.01
	end,
	[32]=function()
		if reaper.GetPlayState()==1 then
			reaper.OnStopButton()
		else
			reaper.OnPlayButton()
		end
	end,
	[30064]=function()
		moveCursorByBeats(quants[movequant])
	end,
	[1685026670]=function()
		moveCursorByBeats(-quants[movequant])
	end,
	[1818584692.0]=function() 
		if movequant==1 then movequant=#quants else movequant=movequant-1 end
	end,
	[1919379572.0]=function() 
		if movequant==#quants then movequant=1 else movequant=movequant+1 end
	end,
	[26161.0]=function() showHelp = not showHelp end
}

local function Main()
	imgScale=math.min(gfx.w,gfx.h)/1024
	local char = gfx.getchar()
	if char ~= -1 then
		reaper.defer(Main)
	end
	playState=reaper.GetPlayState()
	if keyBinds[char] then
        keyBinds[char]()
    end
	-- if char~=0 then
	-- 	reaper.ShowConsoleMsg(tostring(char).."\n")
	-- end	
	

	if diff==4 then
		gfx.blit(1,imgScale,0,0,0,1024,1024,(gfx.w/2)-(imgScale*512),gfx.h-(1024*imgScale)); 
	else
		gfx.blit(0,imgScale,0,0,0,1024,1024,(gfx.w/2)-(imgScale*512),gfx.h-(1024*imgScale));   
	end 
	if playState==1 then
		curBeat=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetPlayPosition())-offset
	end
	curCursorTime=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetCursorPosition())
	if playState~=1  then
		curBeat=curCursorTime
	end
	if curCursorTime~=lastCursorTime then
		lastCursorTime=curCursorTime
	end
	curNote=1
	for i=1,#notes do
		curNote=i
		if notes[i][1]+notes[i][2]>=curBeat then
			break
		end
	end
	curBeatLine=1
	for i=1,#beatLines do
		curBeatLine=i
		if beatLines[i][1]>=curBeat-2 then
			break
		end
	end
	updateEvents()
	updateMidi()
	updateBeatLines()
	drawBeats()
	drawNotes()
	gfx.x,gfx.y=0,0
	gfx.setfont(1, "Arial", 20)
	gfx.drawstr(string.format(
		[[%s %s
		Note: %d/%d
		Current Beat: %.03f
		Snap: %s
		Track Speed: %.02f
		Offset: %.02f
		]],
		diffNames[diff],
		instrumentTracks[inst][1],
		curNote,
		tostring(#notes),
		curBeat,
		toFractionString(quants[movequant]),
		trackSpeed,
		offset
	))
	gfx.x,gfx.y=0,gfx.h-20
	gfx.setfont(1, "Arial", 20)
	gfx.drawstr(string.format("Version %s",version_num))
	strx,stry=gfx.measurestr("Press F1 for controls")
	gfx.x,gfx.y=gfx.w-strx,gfx.h-stry
	gfx.drawstr("Press F1 for controls")
	if showHelp then
		gfx.mode=0
		gfx.r,gfx.g,gfx.b,gfx.a=0,0,0,0.75
		gfx.rect(0,0,gfx.w,gfx.h)
		gfx.r,gfx.g,gfx.b,gfx.a=1,1,1,1
		gfx.x,gfx.y=0,320*imgScale
		gfx.drawstr([[Keybinds
		 
		Change instrument: [ / ]
		Change difficulty: ; / '
		Change track speed: + / -
		Change offset: { / } (Shift + [ / ])
		Change snap: left / right arrows
		Scroll: up/down arrow keys
		]],1,gfx.w,gfx.h)
	end
	gfx.update()
end

Main()