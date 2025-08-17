## Custom Dokploy Installation Script
This script ensures that `1/1: invalid pool request: Pool overlaps with other one on this address space` error doesn't occurs.

### Steps to use this script:
- Create a `install.sh` file.
  ```sh
  nano install.sh
  ```
- Paste the script in that file, then save and exit.
- Make the file executable:
  ```sh
  chmod +x install.sh
  ```
- Make sure you are root user:
  ```sh
  sudo su
  ```
- Execute the script:
  ```sh
  ./install.sh
  ```
