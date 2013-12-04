GithubApi = require('github')
request = require('request')
_ = require('underscore')

exports.getUsedPackages = (repoUrl, cb) ->
  repoHandler = resolveRepoHandler(repoUrl)
  if repoHandler and repoHandler.type == 'github'
    getPackageFiles repoHandler.user, repoHandler.repo, (err, files) ->
      if not err
        if files
          for f in files
            addUsedPackagesInFile(f)
      cb(err, files)


knownPackagers =
  # Regexp to match package specifiers
  'npm': /(^|\/)(package\.json)$/
  'meteor': /(^|\/)(\.meteor\/packages)$/
  'meteor-npm': /(^|\/)(packages\.json)$/
  'meteor-meteorite': /(^|\/)(smart\.json)$/
  'python': /(^|\/)(requirements\.txt)$/
  # 'ruby': /(^|\/)(Gemfile)$/
  # 'java': /(^|\/)(pom\.xml)$/

githubapi = new GithubApi(
  version: "3.0.0"
  protocol: "https")

listFiles = (user, repo, opt_sha ,cb) ->
  sha = 'HEAD' unless opt_sha
  githubapi.gitdata.getTree {user: user, repo: repo, sha: sha, recursive: 1}, (err, res) ->
    if err
      console.log("Error calling getTree with #{user}/#{repo}\##{sha}: #{err}")
      cb(err)
    else
      cb(null, res.tree)


getPackageFiles = (user, repo, cb) ->
  listFiles user, repo, null, (err, files) ->
    if err
      cb(err)
    else
      files = _.filter files, (f) ->
        path = f.path
        for packager, pattern of knownPackagers
          if pattern.test(path)
            f.packager = packager
            f.pattern = pattern
            return true
        return false
      fetchFilesContent files, (err, files) ->
        if err
          cb(err)
        else
          cb(null, files)

fetchFilesContent = (files, cb) ->
  pending = 0
  for f in files
    ++pending
    fetchContent f, (err, res) ->
      if err
        cb(err)
      else
        --pending
        if pending == 0
          cb(null, files)


fetchContent = (file, cb) ->
  request.get file.url, {headers: 'User-Agent': 'NodeJS HTTP Client'}, (err, res, body) ->
    if err
      console.error("Error from github while fetching file content: #{err}")
    else
      if res.statusCode == 200
        data = JSON.parse(body)
        if data.encoding == 'base64'
          file.content = base64decode(data.content)
        else
          console.error("Don't know how to deal with encoding for #{body}")
      else
        console.error("Result code error: #{res}")
    cb(err, res)

base64decode = (encoded) -> new Buffer(encoded || '', 'base64').toString('utf8')

repoHanlers =
  'github': /\bgithub.com\/([^\/]+)\/([^\/]+)\/?.*/

resolveRepoHandler = (repoUrl) ->
  if repoUrl
    for name, pattern of repoHanlers
      if match = repoUrl.match(pattern)
        return {
          type: name
          user: match[1]
          repo: match[2]}

addUsedPackagesInFile = (file) ->
  content = file.content
  packager = resolvePackager(file.packager)
  if packager
    file.packages = packager.getPackages(content)
  else
    console.error("Cannot resolve packager for file #{JSON.stringify(file)}")

resolvePackager = (packagerName) ->
  packagerImplementations[packagerName]

meteorPackager =
  getPackages: (fileContent) ->
    if fileContent
      return fileContent.split('\n').filter((line) -> line.indexOf('#') != 0 and line.trim().length > 0)

pythonPackager =
  getPackages: (fileContent) ->
    if fileContent
      lines = fileContent.split('\n').filter((line) -> line.indexOf('#') != 0 and line.trim().length > 0)
      lines = lines.map (l) -> l.split('==')[0]
      return lines

npmPackager =
  getPackages: (fileContent) ->
    if fileContent
      json = JSON.parse(fileContent)
      _.keys(
        _.reduce(
          _.values(
            _.pick(json, 'dependencies', 'devDependencies', 'optionalDependencies')
          ), ((memo, obj) -> _.extend(memo, obj)), {}))

meteoritePackager =
  getPackages: (fileContent) ->
    if fileContent
      json = JSON.parse(fileContent)
      return _.keys(json.packages)

packagerImplementations =
  'meteor': meteorPackager
  'meteor-npm': npmPackager
  'npm': npmPackager
  'meteor-meteorite': meteoritePackager
  'python': pythonPackager
