## Phlex::TUI

`Phlex::TUI` is pre-alpha and is the current development focus.

It has three main parts:

1. Component system (`Phlex::TUI`)
2. Layout and render pipeline (`Tree`, `Node`, `Render`, `Canvas`)
3. Runtime and input/event system (`App`, `Runtime`, typed events)

### Core classes

- `Phlex::TUI::App`
  - Owns the terminal session and main event loop.
  - Reads keyboard/mouse input, parses input into typed events, dispatches events.
  - Schedules renders on startup and resize.
  - Does not auto-render because an event was dispatched; components call `request_render!` when state changes.

- `Phlex::TUI`
  - Base class for renderable components.
  - Provides DSL methods like `box`, `hstack`, `vstack`, `paragraph`, `span`, `render`.
  - Components can be ephemeral or persistent.

- `Phlex::TUI::Runtime`
  - Frame-local registry of interactive elements.
  - Tracks focusable elements, active dialog scope, focused element.
  - Builds hit maps for mouse hit-testing.
  - Dispatches events directly or with bubbling through parent path.

- `Phlex::TUI::Tree`
  - Structural tree built each frame from component output.
  - Tracks parent/child relationships and stack while rendering.

- `Phlex::TUI::Node` and node subclasses (`Box`, `Paragraph`, `Span`, `Table`, etc.)
  - Immutable-ish frame objects produced by components.
  - Hold layout/style/input metadata used by render and runtime.

- `Phlex::TUI::Render`
  - Converts the tree into drawn terminal cells.
  - Applies layout, clipping, borders, text placement, and style composition.

- `Phlex::TUI::Canvas`
  - Cell buffer for terminal output.
  - Receives draw operations and stores styled cells before final encoding.

- `Phlex::TUI::ANSIEncoder`
  - Encodes styled canvas lines to ANSI escape sequences.

- `Phlex::TUI::FrameDiffer`
  - Diffs previous vs current frame lines.
  - Writes only changed terminal output for performance.

- `Phlex::TUI::Event` + typed events
  - Strongly-typed event objects (e.g. `KeyDownEvent`, `MouseDownEvent`, `MouseWheelEvent`).
  - No hash-style `event[:key]` API.
  - Exposes clear fields/methods (`event.key`, `event.row`, `event.col`, `event.delta_y`, `event.prevent_default!`, `event.stop_propagation!`).

### Event model

- Mouse events
  - Hit-test target from runtime hit map using event coordinates.
  - Dispatch to target, then bubble through parent chain until propagation is stopped.

- Keyboard events
  - Target is the currently focused element.
  - Dispatch + bubble with the same propagation model.

- Rendering rule
  - Event dispatch itself never implies rerender.
  - Components must call `request_render!` when internal state changes.

### Component lifetime

Persistent components keep state across frames and should be stored as ivars.
Ephemeral components are instantiated per frame.

Example:

```ruby
class Example < Phlex::TUI
	def initialize
		@scroller = SomeScrollerComponent.new
	end

	def view_template
		Button { "Hello" }
		render @scroller
	end
end
```

## Testing

Run the full suite with `bundle exec qt`.
Do not run individual tests unless explicitly requested.

## Coding style

1. Prefer case statements or `===` over `is_a?`
2. Avoid using `respond_to?`. It’s better to give objects no-op methods than check if they respond to a method.
3. Avoid unnecessary object allocations, especially in tight loops.
4. In tight array loops, prefer `while` over `each`
5. Use data-oriented design principles to optimize performance. Think about how data is cached and accessed.
6. Use modifiers, e.g. `private def foo` where `private` is on the same line as the definition.
7. Prefer `NoMethodError` over `NotImplementedError` when defining a method that a subclass should implement.
8. Prefer `case` / `in` over `case` / `when` because it automatically raises if a missing else case is hit.
9. Don’t try to gloss over errors. If there is something wrong, the system should raise. In the long run, this will help us make the system more robust.
