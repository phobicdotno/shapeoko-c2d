# New-C2d-18Holes.ps1
# Builds a modern (v7/v8 SQLite) Carbide Create .c2d containing the Shapeoko 3 XXL
# baseplate's 18 counterbored mounting holes, by cloning an existing v8 file as a
# structural template. Windows PowerShell 5.1, no dependencies (uses winsqlite3.dll).
# Usage: .\New-C2d-18Holes.ps1 <template.c2d> <output.c2d>
$ErrorActionPreference='Stop'

Add-Type -Path (Join-Path $PSScriptRoot 'winsqlite.cs')
$ci=[Globalization.CultureInfo]::InvariantCulture
$TRANSIENT=[IntPtr]::op_Explicit(-1)

function Zlib([byte[]]$data){
  # zlib = 0x78 0x9C + raw deflate + adler32(BE)
  $ms=New-Object IO.MemoryStream
  $ds=New-Object IO.Compression.DeflateStream($ms,[IO.Compression.CompressionMode]::Compress,$true)
  $ds.Write($data,0,$data.Length); $ds.Close()
  $defl=$ms.ToArray()
  $a=1;$b=0
  foreach($byte in $data){ $a=($a+$byte)%65521; $b=($b+$a)%65521 }
  $adler=($b*65536+$a)
  $out=New-Object byte[] ($defl.Length+6)
  $out[0]=0x78; $out[1]=0x9C
  [Array]::Copy($defl,0,$out,2,$defl.Length)
  $out[$out.Length-4]=[byte](($adler -shr 24) -band 0xFF)
  $out[$out.Length-3]=[byte](($adler -shr 16) -band 0xFF)
  $out[$out.Length-2]=[byte](($adler -shr 8) -band 0xFF)
  $out[$out.Length-1]=[byte]($adler -band 0xFF)
  return ,$out
}
function N([double]$v){ $v.ToString('R',$ci) }

function CircleJson([double]$x,[double]$y,[double]$r,[string]$id){
  $k=$r*0.5522847498307936
  $rs=N $r; $ks=N $k; $xs=N $x; $ys=N $y
  $nk=N (-$k); $nr=N (-$r)
@"
{
    "behavior": 3,
    "center": [
        $xs,
        $ys
    ],
    "cp1": [
        [
            0,
            0
        ],
        [
            $nr,
            $ks
        ],
        [
            $ks,
            $rs
        ],
        [
            $rs,
            $nk
        ],
        [
            $nk,
            $nr
        ],
        [
            0,
            0
        ]
    ],
    "cp2": [
        [
            0,
            0
        ],
        [
            $nk,
            $rs
        ],
        [
            $rs,
            $ks
        ],
        [
            $ks,
            $nr
        ],
        [
            $nr,
            $nk
        ],
        [
            0,
            0
        ]
    ],
    "geometryType": "circle",
    "group_id": [
    ],
    "id": "$id",
    "layer": {
        "blue": 0,
        "green": 0,
        "locked": false,
        "name": "DEFAULT",
        "red": 0,
        "uuid": "",
        "visible": true
    },
    "point_type": [
        0,
        3,
        3,
        3,
        3,
        4
    ],
    "points": [
        [
            $nr,
            0
        ],
        [
            0,
            $rs
        ],
        [
            $rs,
            0
        ],
        [
            0,
            $nr
        ],
        [
            $nr,
            0
        ],
        [
            0,
            0
        ]
    ],
    "position": [
        $xs,
        $ys
    ],
    "radius": $rs,
    "smooth": [
        1,
        1,
        1,
        1,
        1,
        1
    ],
    "tabs": [
    ]
}
"@
}

# --- 1) clone template ---
$src=$args[0]; if(-not $src){ $src='Shapeoko-XXL-Wasteboard_v8.c2d' }
$dst=$args[1]; if(-not $dst){ $dst='Shapeoko-3-XXL-Baseplate-18-Mounting-Holes-No-Path.c2d' }
Copy-Item $src $dst -Force
Write-Output "cloned template -> $dst"

# --- 2) open read-write ---
$db=[IntPtr]::Zero
$rc=[WinSqlite]::sqlite3_open_v2([WinSqlite]::Utf8($dst),[ref]$db,2,[IntPtr]::Zero)  # READWRITE
if($rc -ne 0){ throw "open failed rc=$rc" }

function Exec($sql){
  $st=[IntPtr]::Zero
  $rc=[WinSqlite]::sqlite3_prepare_v2($db,[WinSqlite]::Utf8($sql),-1,[ref]$st,[IntPtr]::Zero)
  if($rc -ne 0){ throw "prepare '$sql': $([WinSqlite]::PtrToUtf8([WinSqlite]::sqlite3_errmsg($db)))" }
  $r=[WinSqlite]::sqlite3_step($st)
  [void][WinSqlite]::sqlite3_finalize($st)
  if($r -ne 101){ throw "step '$sql' rc=$r : $([WinSqlite]::PtrToUtf8([WinSqlite]::sqlite3_errmsg($db)))" }
}

Exec "BEGIN"
# --- 3) strip old geometry + toolpaths, keep layer/group/model ---
Exec "DELETE FROM items WHERE type='element'"
Exec "DELETE FROM items WHERE type='toolpath'"
Exec "DELETE FROM log"
# --- 4) params: new board size, no toolpaths ---
Exec "UPDATE params SET value='1066.8' WHERE key='width'"
Exec "UPDATE params SET value='1003.3' WHERE key='height'"
Exec "UPDATE params SET value='0' WHERE key='num_toolpaths'"
Exec "UPDATE params SET value='19.05' WHERE key='thickness'"
# --- 5) blank stale renders/gcode (mirror background.png's empty row) ---
Exec "UPDATE sqlar SET sz=0, data=x'' WHERE name IN ('all.svg','preview.svg','gcode.egc')"

# --- 6) insert 36 circles ---
$outerX=@(25.4,127.0,482.6,584.2,939.8,1041.4)
$midX=@(76.2,533.4,990.6)
$holes=@()
$outerX | ForEach-Object { $holes+=,@($_,15.00) }
$midX   | ForEach-Object { $holes+=,@($_,476.25) }
$midX   | ForEach-Object { $holes+=,@($_,527.05) }
$outerX | ForEach-Object { $holes+=,@($_,988.30) }

$ins="INSERT INTO items(uuid,name,type,version,sz,data) VALUES(?,?,?,?,?,?)"
$count=0
foreach($r in @(6.35,2.54)){
  foreach($h in $holes){
    $id='{'+[guid]::NewGuid().ToString()+'}'
    $json=CircleJson $h[0] $h[1] $r $id
    $json=$json -replace "`r`n","`n"
    $plain=[Text.Encoding]::UTF8.GetBytes($json)
    $comp=Zlib $plain
    $st=[IntPtr]::Zero
    $rc=[WinSqlite]::sqlite3_prepare_v2($db,[WinSqlite]::Utf8($ins),-1,[ref]$st,[IntPtr]::Zero)
    if($rc -ne 0){ throw "prepare insert: $([WinSqlite]::PtrToUtf8([WinSqlite]::sqlite3_errmsg($db)))" }
    $u=[Text.Encoding]::UTF8.GetBytes($id)
    [void][WinSqlite]::sqlite3_bind_text($st,1,$u,$u.Length,$TRANSIENT)
    $n1=[Text.Encoding]::UTF8.GetBytes('circle')
    [void][WinSqlite]::sqlite3_bind_text($st,2,$n1,$n1.Length,$TRANSIENT)
    $n2=[Text.Encoding]::UTF8.GetBytes('element')
    [void][WinSqlite]::sqlite3_bind_text($st,3,$n2,$n2.Length,$TRANSIENT)
    $n3=[Text.Encoding]::UTF8.GetBytes('J1')
    [void][WinSqlite]::sqlite3_bind_text($st,4,$n3,$n3.Length,$TRANSIENT)
    [void][WinSqlite]::sqlite3_bind_int($st,5,$plain.Length)
    [void][WinSqlite]::sqlite3_bind_blob($st,6,$comp,$comp.Length,$TRANSIENT)
    $r2=[WinSqlite]::sqlite3_step($st)
    [void][WinSqlite]::sqlite3_finalize($st)
    if($r2 -ne 101){ throw "insert rc=$r2 : $([WinSqlite]::PtrToUtf8([WinSqlite]::sqlite3_errmsg($db)))" }
    $count++
  }
}
Exec "COMMIT"
Write-Output "inserted $count circle elements"
[void][WinSqlite]::sqlite3_close_v2($db)
Write-Output "done: $((Get-Item $dst).Length) bytes"
