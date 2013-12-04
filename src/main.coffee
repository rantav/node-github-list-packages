list = require('./list')

if process.argv.length < 3
  console.error("Usage: pass a github url, for example https://github.com/rantav/devdev")
else
  list.getUsedPackages process.argv[2], (err, files) ->
    if err
      console.error(err)
    else
      console.log(files)
