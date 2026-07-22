# JLCPCB Component Price Fetcher

## Overview
This script fetches real-time pricing data for electronic components from JLCPCB and calculates accurate costs for PCB assembly at configurable production volumes. It uses dynamic pricing with all available quantity tiers and configurable board quantities.

## Usage
```bash
./fetch_jlcpcb_prices.py <part_numbers_file>
```

A filename parameter is required.

## Input File Format
The `part_numbers.txt` file supports:

### Multiple Component Groups
Groups are separated by empty lines. Each group gets its own pricing table.

### Table Titles
The first comment line (starting with `#`) in each group becomes the table title.

### Component Format
```
part_number quantity_per_board  # optional comment
```

### Example File
```
# ESP32 RAW design, 8MB flash + 8MB ram
C2913194  1  # ESP32-S3R8, integrated 8MB ram
C2685734  1  # GD25Q64ESIG, 8MB flash
C37635410 1  # 40 MHz crystal 
C5137195  1  # IPEX connector

# ESP32 module with integrated antenna, 8MB flash + 2MB ram
C2913204 1  # ESP32-S3-WROOM-1-N8R2

# MOSFET driver
C8545    12  # N-ch mosfet (12 pieces per board)
C15127   3   # P-ch mosfet
C167994  3   # Inductor 8m2
```

## Features

### Dynamic Quantity-Based Pricing
The script fetches ALL available quantity/price tiers from JLCPCB instead of hardcoding specific quantities. For each board quantity requested, it automatically selects the best bulk pricing tier available.

- Fetches complete pricing information (all quantity breaks)
- Calculates actual quantities needed: `pieces_per_board × board_count`
- Automatically selects optimal bulk pricing tier for each quantity
- Supports any board quantities (not limited to 1/50/500)

### Automatic PCBA Type Detection
- **Basic Parts (B)**: No setup fee, widely available components
- **Extended Parts (-)**: $3 setup fee per unique component
- **Economic Parts (E)**: Available for economic PCBA assembly

Detection looks for "Basic" tags next to component names on JLCPCB pages.

### Setup Fee Calculation
- Setup fees are charged per unique non-Basic component
- Setup fee is divided by number of boards produced
- Shows both per-board setup cost and total per-board price

### Multiple Output Tables
Each component group generates a separate table using the Board class showing:
- Component name and part number
- Pieces per board
- PCBA type (Basic/Economic)
- Unit prices for configurable board production runs (default: 1/50/500)
- Total cost per component type
- Setup fees per board
- Final price per board
- Left-aligned formatting with proper column widths

### Output Files
- Tables are displayed on the console during execution
- All tables are automatically saved to a markdown file with `.table.md` extension
- For example: `./fetch_jlcpcb_prices.py parts.txt` creates `parts.table.md`

## Output Example
```
ESP32 RAW design, 8MB flash + 8MB ram
=====================================
Component              | Number    | Pcs | Base | Eco | 1 pcs   | 50 pcs  | 500 pcs 
-----------------------------------------------------------------------------------
ESP32-S3R8             | C2913194  | 1   | -    | E   | 3.6210  | 2.5800  | 2.5800
GD25Q64ESIG            | C2685734  | 1   | -    | E   | 0.6210  | 0.4740  | 0.2730
-----------------------------------------------------------------------------------
TOTAL                  |           |     |      |     | 4.2420  | 3.0540  | 2.8530
SETUP FEE PER BOARD    |           |     |      |     | 6.0000  | 0.1200  | 0.0120
-----------------------------------------------------------------------------------
PRICE PER BOARD        |           |     |      |     | 10.2420 | 3.1740  | 2.8650
```

## Requirements
- Python 3 with requests and beautifulsoup4 packages
- Uses nix-shell for dependency management:
  ```bash
  nix-shell -p python313 python313Packages.requests python313Packages.beautifulsoup4
  ```

## Rate Limiting
The script includes 2-second delays between requests to be respectful to JLCPCB's servers.

## Error Handling
- Validates input file format
- Handles network timeouts and errors gracefully
- Reports failed component fetches
- Continues processing remaining components if some fail

## Use Cases
- Compare costs between raw components vs integrated modules
- Determine optimal production quantities for cost efficiency
- Calculate accurate PCB assembly budgets
- Evaluate component selection impact on total costs

## Code Architecture

### Component Class
The script uses a `Component` class that encapsulates all component-related data and operations:

```python
class Component:
    def __init__(self, part_number: str)
    def get_unit_price(self, board_count: int, pieces_per_board: int = 1) -> Optional[float]
    def get_total_price(self, board_count: int, pieces_per_board: int) -> Optional[float]
    def fetch_from_jlcpcb(self, pieces_per_board: int = 1) -> bool
    def is_basic_part() -> bool
    def get_setup_fee_contribution() -> float
    def set_component_data(self, name: str, base_type: str, eco_type: str, available_quantities: List[Tuple[int, float]]) -> None
```

Key changes:
- **Dynamic Pricing Storage**: Components store `available_quantities: List[Tuple[int, float]]` instead of hardcoded price dictionary
- **Smart Price Matching**: `get_unit_price()` finds best bulk pricing tier based on actual quantity needed
- **All Quantity Tiers**: `_extract_pricing()` fetches ALL available quantity/price pairs from JLCPCB

### Board Class
The script uses a `Board` class to manage groups of components and render tables:

```python
class Board:
    def __init__(self, title: Optional[str] = None, board_quantities: Optional[List[int]] = None)
    def add_component(self, component: Component, quantity: int) -> None
    def get_components(self) -> List[Tuple[Component, int]]
    def calculate_totals(self) -> Dict[int, float]
    def calculate_setup_fee(self) -> float
    def render_table(self) -> str
    def display_table(self) -> str
```

Key features:
- **Configurable Quantities**: Accepts custom board quantities (default: [1, 50, 500])
- **Dynamic Table Rendering**: Generates tables with proper column widths and left-alignment
- **Flexible Range**: Supports 1-6 different quantities, automatically adjusting table width
- **Dual Output**: `render_table()` returns content, `display_table()` prints and returns content
- **Markdown Export**: Tables are automatically saved to `.table.md` files

### Design Principles
- **Type Safety**: All methods use proper type annotations with `int` for board counts and quantities
- **Dynamic Pricing**: No hardcoded quantities - fetches all available pricing tiers
- **Separation of Concerns**: Component pricing separate from Board table rendering
- **Clean API**: Board quantities configurable, Components handle optimal pricing selection
- **Proper Formatting**: Left-aligned tables with consistent column widths using f-string formatting

### Development Guidelines
- Use `mypy` for type checking: `mypy --ignore-missing-imports --disable-error-code=import-untyped`
- Use `ruff` for linting: `ruff check`
- Follow type-safe practices: use `Dict[int, float]` for totals, not string keys
- Use Board class for table rendering with configurable quantities
- Components should store all available pricing tiers, not hardcoded quantities
- Table formatting should use proper f-string width specifiers, all left-aligned
- Maintain backwards compatibility with existing part_numbers.txt format

### Architecture Rules
- **NO hardcoded quantities**: Always fetch all available quantity/price pairs
- **Use Board class**: Each component group becomes a Board instance
- **Dynamic pricing**: Components select best pricing tier automatically
- **Left-aligned tables**: All columns use `:<width` formatting, no arbitrary spaces
