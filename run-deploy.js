const { spawn } = require("child_process");
const path = require("path");

// Resolve the absolute path to your shell script
const scriptPath = path.join(__dirname, "deploy.sh");

console.log(`Starting deployment via Node wrapper: ${scriptPath}`);

// Spawn the shell script as a child process.
// Passing process.env ensures it inherits the GEMINI_API_KEY loaded by Node.
const deployProcess = spawn("bash", [scriptPath], {
  env: process.env,
  stdio: "inherit", // This streams the terminal output (stdout/stderr) in real-time
});

deployProcess.on("close", (code) => {
  if (code === 0) {
    console.log("Deployment completed successfully!");
  } else {
    console.error(`Deployment script exited with error code ${code}`);
    process.exit(code);
  }
});
