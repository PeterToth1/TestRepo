
New-Item -itemtype directory -name "files" -Force
Set-Location .\files

for ($i=1; $i -le 10; $i++) {
	echo $i,"Poida is a champ`nPoida is a champ`nPoida is a champ`n" > "file ${i}.txt" 
}

Compress-Archive '.\*.*' '..\files.zip'

# Start-Sleep -Seconds 30


