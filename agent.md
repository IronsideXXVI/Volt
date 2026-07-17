#What this project is
- This project is a Mac OS app for tracking AI usage limits across various usage plans from various providers.
- The app is a menu bar application that users access at any time via the mac os menu bar to view their usage limits
- The git repo has two branches that we use for development.. a main branch, and a dev branch
- The main branch will be used for complete prod ready builds based on dev that are approved by me, Dylan.
- The dev branch is used for development and testing before a build is pushed to prod, any updates made to the code, or PRs should be built on top of dev, unless I (Dylan) say otherwise, eg. if I want to push something to Prod.
- The app should have automatic and manual updates using Sparkle, and each release should have release notes that the user is able to read.
- Any time that something is pushed to prod, it should automaticly cut a release based on prod and sparkle should pick up the new build.

#plan
- At first I want to support two diffrent usage plans, Claude, and OpenAI.
- The overal UI/UX and logic should be extremly simalar to my Claude usage app found in my git account called Claude usage, but with an additional option to switch between providers, and having auto updates.
- Much of the auto update process and logic can be found in my repo called Hacker News. We can take logic from that for this project.

#Use progress.md to keep notes, and keep track of progress. Anytime you're starting a new session, be sure to fully read progress md, then compare it to what's actually in the codebase right now to make sure it's accurate and up to date. If anything in progress md needs updating, then update it.
#Whenever you have a question, or need somthing from me on my end, do not hesitate to ask.