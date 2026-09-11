Drop your PDF or video walkthrough files directly into this folder (in
Finder or in Xcode).

Then open Data/ProgramData.swift and, for a `.local` program, add a
WalkthroughResource with `location: .bundled(filename: "...")` set to the
file's exact name, including its extension -- e.g.
.bundled(filename: "Site Safety Plan.pdf")

This folder is added to the app as a folder reference, so anything you put
here gets bundled with the app automatically -- no extra steps in Xcode.
