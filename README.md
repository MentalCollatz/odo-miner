OdoCrypt FPGA Miner
===================

Requirements
------------

Currently only supports Intel (Altera) FPGAs on Linux hosts.

Installing Quartus Prime
------------------------

Quartus prime is required to both compile and run this miner.  It is currently available at
`<https://fpgasoftware.intel.com/>`_ .  To figure out what edition you need, check the device
support list.  To minimize your download, choose the Individual Files tab, then download only
Quartus Prime, and the device support files for the devices you're using.  Install according
to the instructions on their website.

After installing, set the variable ``QUARTUSPATH`` to point to the ``quartus/bin`` directory of
your installation.  For example ``export QUARTUSPATH="/home/miner/altera/18.1/quartus/bin`` .
This line should be added to your ``~/.profile`` file or another file that is sourced whenever a
shell is launched.  Don't forget to source the file after editing it.

Additional Files
----------------

You need to install a custom udev rule in order to allow a non-root user access to FPGA hardware.

* Open ``99-altera.rules``, and change the ``1000`` on the last line to your user id.  Alternatively, run ``sed -i s/1000/$(whoami)/ 99-altera.rules`` (don't run this command as root).
* Run ``sudo cp 99-altera.rules /etc/udev/rules.d/``
* Run ``sudo udevadm control --reload``

Connecting Your Hardware
------------------------

Notice: It is highly recommended that you remove the acrylic cover on your development kit (if it comes with one) to prevent it from overheating.

* Connect one end of your development kit's USB cable to your computer, and the other end to the development kit.  If your development kit has multiple USB ports, be sure to connect to the one labelled "USB Blaster".
* Connect your development kit's power cable, and turn on the device.
* Verify the presence of your device by running ``lsusb | grep Altera`` (this should output one line per development kit).
* Further verify your setup by running ``$QUARTUSPATH/jtagconfig`` (this will list all of your recognised development kits)

Starting to Mine
----------------

TODO.  For now, try running the command ``./compile.sh cyclone_v_gx_starter_kit 0`` to compile a test file.
