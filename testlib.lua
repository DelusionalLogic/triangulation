local testlib = {}

function testlib.run() 
	tests = 0
	local failures = 0
	local testroot = "test"
	local testfiles = love.filesystem.getDirectoryItems(testroot)
	for _, filename in ipairs(testfiles) do
		local testname = (filename:gsub(".lua", ""))
		io.write(testname, "\n")
		local file = loadfile(testroot .. "/" .. filename)
		local status, value = pcall(file)
		if status then
			io.write("    ...   SUCCESS\n")
		else
			if value then
				io.write(value, "\n")
			end
			io.write("    ...   FAILED\n")
			failures = failures + 1
		end
	end

	io.write(tests - failures, "/", tests, "\n")
	if failures > 0 then
		os.exit(1)
	else
		os.exit(0)
	end
end

return testlib
