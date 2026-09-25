// Writes a snapshot shaped exactly as musterd marshals model.Snapshot, for
// muster-omarchy's tests. Times are fixed so the tests can pin "now".
package main

import (
	"encoding/json"
	"os"
	"time"

	"fixturegen/model"
)

func main() {
	loc := time.FixedZone("", 2*3600)
	gen := time.Date(2026, 9, 25, 12, 0, 0, 123456789, loc)
	ago := func(d time.Duration) time.Time { return gen.Add(-d) }

	snap := model.Snapshot{
		GeneratedAt:  gen,
		DaemonPID:    4242,
		HerdrVersion: "0.9.0",
		Workspaces: []model.Workspace{
			{ID: "w1", Number: 1, Label: "api"},
			{ID: "w2", Number: 2, Label: "web"},
			{ID: "w3", Number: 3, Label: "scratch"},
		},
		Repos: []model.Repo{
			{
				Key: "acme/api", Name: "api", Display: "api", Root: "/src/api", Branch: "main", IsGit: true,
				ColorIndex: 12, Sigil: "✦", GridSlot: 0, WorkspaceIDs: []string{"w1"},
				Agents: []model.Agent{
					{PaneID: "w1:p1", WorkspaceID: "w1", TabID: "t1", Name: "orchestrator", Kind: "claude",
						Status: model.StatusIdle, TaskSource: model.TaskFromNone, StatusSince: ago(3 * time.Minute),
						AgeKnown: true, IsOrchestrator: true},
					{PaneID: "w1:p2", WorkspaceID: "w1", TabID: "t1", Name: "fixer", Kind: "codex",
						Status: model.StatusBlocked, Task: "fix the flaky test", TaskSource: model.TaskFromOrchestrator,
						Question: "Allow rm -rf build/?", StatusSince: ago(90 * time.Second), AgeKnown: true},
					{PaneID: "w1:p3", WorkspaceID: "w1", TabID: "t1", Name: "docs", Kind: "claude",
						Status: model.StatusWorking, TaskSource: model.TaskFromSelfReport, StatusSince: ago(40 * time.Second),
						AgeKnown: true},
				},
				OtherPanes: []model.Pane{{PaneID: "w1:p9", WorkspaceID: "w1", Label: "dev server", Command: "npm run dev"}},
			},
			{
				Key: "acme/web", Name: "web", Display: "web", Root: "/src/web", Branch: "feature/login", IsGit: true,
				ColorIndex: 4, Sigil: "◆", GridSlot: 1, WorkspaceIDs: []string{"w2"},
				Agents: []model.Agent{
					{PaneID: "w2:p1", WorkspaceID: "w2", TabID: "t2", Name: "login", Kind: "claude",
						Status: model.StatusIdle, Task: "wire the login form", TaskSource: model.TaskFromOrchestrator,
						DependsOn: "api#412", DependsOnRepo: "acme/api", LandedAt: ago(10 * time.Minute),
						StatusSince: ago(2 * time.Hour), AgeKnown: true},
					{PaneID: "w2:p2", WorkspaceID: "w2", TabID: "t2", Name: "styles", Kind: "claude",
						Status: model.StatusDone, TaskSource: model.TaskFromTerminalTitle, StatusSince: ago(5 * time.Minute),
						AgeKnown: false},
				},
			},
			{
				Key: "/tmp/scratch", Name: "scratch", Display: "scratch", Root: "/tmp/scratch", IsGit: false,
				ColorIndex: -1, Sigil: "○", GridSlot: -1, WorkspaceIDs: []string{"w3"},
				Agents: []model.Agent{},
			},
		},
		Attention: []model.Attention{
			{Rank: 1, Reason: model.ReasonBlocked, RepoKey: "acme/api", PaneID: "w1:p2", Agent: "fixer",
				Status: model.StatusBlocked, Age: 90 * time.Second, AgeKnown: true, Detail: "Allow rm -rf build/?"},
			{Rank: 2, Reason: model.ReasonLanded, RepoKey: "acme/web", PaneID: "w2:p1", Agent: "login",
				Status: model.StatusIdle, Age: 2 * time.Hour, AgeKnown: true, Detail: "api#412 landed, nobody moved",
				Dependents: []string{"web/login"}},
			{Rank: 3, Reason: model.ReasonProcessStopped, RepoKey: "acme/api", PaneID: "w1:p9", Agent: "dev server",
				Status: model.StatusUnknown, AgeKnown: false, Detail: "npm run dev\nexited"},
			{Rank: 4, Reason: model.ReasonDoneUnseen, RepoKey: "acme/web", PaneID: "w2:p2", Agent: "styles",
				Status: model.StatusDone, Age: 5 * time.Minute, AgeKnown: false},
			{Rank: 5, Reason: model.ReasonIdleNeverDone, RepoKey: "acme/api", PaneID: "w1:p1", Agent: "orchestrator",
				Status: model.StatusIdle, Age: 3 * time.Minute, AgeKnown: true, Detail: "idle since its last turn"},
		},
		Orch: model.Orchestrator{
			Found: true, PaneID: "w1:p1", Name: "orchestrator", Status: model.StatusIdle,
			LastMessage: "coordinate the login work",
			LastSaid:    "api#412 is merged.\nTelling web to pick it up next.",
			SaidAt:      ago(45 * time.Second), DetectedBy: "token", StatusSince: ago(3 * time.Minute),
		},
		FocusedWorkspace: "w1", FocusedPane: "w1:p3", PreviousAgent: "w2:p1",
		FocusHistory: []string{"w1:p3", "w2:p1"},
		Counts:       model.Counts{Repos: 3, Workspaces: 3, Agents: 5, NeedsYou: 5, Working: 1, NonAgents: 1},
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(snap); err != nil {
		panic(err)
	}
}
