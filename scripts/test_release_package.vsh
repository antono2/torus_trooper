// Run the relocated desktop package verifier from the command line.
import os
import scripts.releaseconsumer

releaseconsumer.smoke(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
