# Helper script to execute Ansible playbooks inside the edge-ansible-runner Docker container
$sshDir = "$HOME\.ssh"
$workDir = (Get-Location).Path

if ($args.Count -eq 0) {
    Write-Host "Usage: .\scripts\run_ansible.ps1 -i ansible/inventory.yml <playbook.yml> [options]"
    exit 1
}

docker run --rm `
  -e ANSIBLE_CONFIG=/work/ansible/ansible.cfg `
  -v "${workDir}:/work" `
  -v "${sshDir}:/mnt/ssh:ro" `
  edge-ansible-runner @args
