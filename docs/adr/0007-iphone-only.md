# Support iPhone only

On 2026-11-04, the product scope changed to iPhone only so development and verification can focus on one device family. Remove native iPad layouts, targets and UI coverage; retain the iPhone workflows, Share extension and task-data behavior. External keyboard commands and widgets were removed by a subsequent product decision on 2026-11-17.

iPad support can be reconsidered as a separate future product decision. Historical iPad requirements and verification reports do not define current acceptance. Measure the complete iPhone suite, including build and setup, before deciding whether to require it on every pull request.
