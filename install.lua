local internet = require("internet")
local filesystem = require("filesystem")
local json
local function checkAndDownloadJson()
  local jsonPath = "/lib/json.lua"
  if not filesystem.exists(jsonPath) then
    print("json.lua not found. Downloading...")
    os.execute("wget https://raw.githubusercontent.com/rxi/json.lua/master/json.lua -O " .. jsonPath)
  else
    json = require("json")
  end
end

-- Вызов функции проверки и загрузки json.lua
checkAndDownloadJson()

local function parseGitHubUrl(url)
  local user, repo = url:match("github.com/([^/]+)/([^/]+)/?")
  return user, repo
end

local function httpGet(url)
  local handle = internet.request(url, nil, { 
    ["Cache-Control"] = "no-cache" 
  })
  local result = ""
  for chunk in handle do
    result = result .. chunk
  end
  return result
end

local function ensureDir(path)
  if not filesystem.exists(path) then
    filesystem.makeDirectory(path)
  end
end

local function downloadFile(user, repo, branch, path, savePath)
  local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", user, repo, branch, path)
  print("Downloading " .. path)
  local content = httpGet(url)

  -- Если файл существует — удаляем
  if filesystem.exists(savePath) then
    filesystem.remove(savePath)
  end

  local file = io.open(savePath, "w")
  if not file then
    print("Failed to open file for writing: " .. savePath)
    return
  end
  file:write(content)
  file:close()
end

local function install(repoUrl, branch)
  branch = branch or "main"
  local user, repo = parseGitHubUrl(repoUrl)
  if not user or not repo then
    print("Invalid GitHub repository URL")
    return
  end

  print(string.format("Installing from %s/%s branch %s", user, repo, branch))

  local apiUrl = string.format("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1", user, repo, branch)
  local treeJson = httpGet(apiUrl)
  local treeData = json.decode(treeJson)

  if not treeData or not treeData.tree then
    print("Failed to get file list from GitHub API.")
    return
  end

  local basePath = "/home"

  for _, entry in ipairs(treeData.tree) do
    if entry.type == "blob" then
      local filePath = basePath .. "/" .. entry.path
      ensureDir(filesystem.path(filePath))
      downloadFile(user, repo, branch, entry.path, filePath)
    elseif entry.type == "tree" then
      ensureDir(basePath .. "/" .. entry.path)
    end
  end

  print("Installation completed.")
end

-- Читаем аргументы из командной строки
local repoUrl = ...
if not repoUrl then
  print("Usage: install.lua <GitHub repo URL> [branch]")
  return
end
local branch = select(2, ...)

install(repoUrl, branch)
