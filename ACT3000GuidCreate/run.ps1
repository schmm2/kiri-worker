param($name)

# create guid
$guid = $([Guid]::NewGuid().ToString())
return $guid
