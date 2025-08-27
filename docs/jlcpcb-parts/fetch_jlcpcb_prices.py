#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python313 python313Packages.requests python313Packages.beautifulsoup4

import requests
from bs4 import BeautifulSoup
import re
import sys
import time
from typing import Dict, List, Optional, Tuple


class Component:
    """Class to handle component data and pricing calculations."""
    
    def __init__(self, part_number: str):
        self.part_number = part_number
        self.component_name = "Unknown"
        self.base_type = "-"
        self.eco_type = "-"
        self.available_quantities: List[Tuple[int, float]] = []
    
    def get_part_number(self) -> str:
        """Get the part number."""
        return self.part_number
    
    def get_component_name(self) -> str:
        """Get the component name."""
        return self.component_name
    
    
    def get_base_type(self) -> str:
        """Get base type (B for Basic, - for Extended)."""
        return self.base_type
    
    def get_eco_type(self) -> str:
        """Get economic type (E for Economic, - for regular)."""
        return self.eco_type
    
    def is_basic_part(self) -> bool:
        """Check if component is a Basic part (no setup fee)."""
        return self.base_type == "B"
    
    def get_setup_fee_contribution(self) -> float:
        """Get setup fee contribution (0 for Basic parts, 3.0 for others)."""
        return 0.0 if self.is_basic_part() else 3.0
    
    def get_unit_price(self, board_count: int, pieces_per_board: int = 1) -> Optional[float]:
        """Get unit price for given board count, finding best match from available quantities."""
        if not self.available_quantities:
            return None
        
        target_qty = board_count * pieces_per_board
        best_match = None
        
        # Find the highest quantity that's <= target_qty (bulk pricing)
        for qty, price in self.available_quantities:
            if qty <= target_qty:
                best_match = (qty, price)
            else:
                break
        
        # If no quantity is <= target_qty, use the smallest available quantity
        if best_match is None:
            best_match = self.available_quantities[0]
        
        return best_match[1] if best_match else None
    
    def get_total_price(self, board_count: int, pieces_per_board: int) -> Optional[float]:
        """Get total price for this component at given board count (unit_price * pieces_per_board)."""
        unit_price = self.get_unit_price(board_count, pieces_per_board)
        if unit_price is None:
            return None
        return unit_price * pieces_per_board
    
    def get_target_quantity(self, board_count: int, pieces_per_board: int) -> int:
        """Get target quantity needed for given board count."""
        return pieces_per_board * board_count
    
    def set_component_data(self, name: str, base_type: str, eco_type: str, available_quantities: List[Tuple[int, float]]) -> None:
        """Set component data after fetching from JLCPCB."""
        self.component_name = name
        self.base_type = base_type
        self.eco_type = eco_type
        self.available_quantities = available_quantities.copy()
    
    def fetch_from_jlcpcb(self, pieces_per_board: int = 1) -> bool:
        """Fetch component data from JLCPCB and populate the object."""
        url = f"https://jlcpcb.com/partdetail/{self.part_number}"
        
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept-Encoding': 'gzip, deflate, br',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1'
        }
        
        try:
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Extract component data
            component_name = self._extract_component_name(soup)
            base_type, eco_type = self._extract_pcba_types(soup)
            available_quantities = self._extract_pricing(soup)
            
            # Set the data
            self.set_component_data(component_name, base_type, eco_type, available_quantities)
            return True
            
        except requests.RequestException as e:
            print(f"Error fetching {self.part_number}: {e}")
            return False
    
    def _extract_component_name(self, soup: BeautifulSoup) -> str:
        """Extract component name from soup."""
        selectors = [
            'h1',
            '.part-title',
            '.component-name',
            '[data-testid="part-name"]'
        ]
        
        for selector in selectors:
            element = soup.select_one(selector)
            if element:
                name = element.get_text(strip=True)
                if name:
                    return name
        
        return "Unknown"
    
    def _extract_pcba_types(self, soup: BeautifulSoup) -> Tuple[str, str]:
        """Extract PCBA base and eco types."""
        base_type = "-"
        eco_type = "-"
        
        page_text = soup.get_text()
        
        if re.search(r'\bBasic\b', page_text, re.IGNORECASE):
            base_type = "B"
        
        if re.search(r'\bExtended\b', page_text, re.IGNORECASE):
            base_type = "-"
        
        title_elements = soup.find_all(['h1', 'h2', 'h3', 'title'])
        for element in title_elements:
            element_text = element.get_text()
            if re.search(r'\bBasic\b', element_text, re.IGNORECASE):
                base_type = "B"
            if re.search(r'\bExtended\b', element_text, re.IGNORECASE):
                base_type = "-"
        
        tag_elements = soup.find_all(['span', 'div', 'badge', 'label'], string=re.compile(r'\bBasic\b|\bExtended\b', re.I))
        for element in tag_elements:
            element_text = element.get_text()
            if re.search(r'\bBasic\b', element_text, re.IGNORECASE):
                base_type = "B"
            if re.search(r'\bExtended\b', element_text, re.IGNORECASE):
                base_type = "-"
        
        pcba_text_upper = page_text.upper()
        if 'ECONOMIC' in pcba_text_upper and 'PCBA' in pcba_text_upper:
            eco_type = "E"
        
        return base_type, eco_type
    
    def _extract_pricing(self, soup: BeautifulSoup) -> List[Tuple[int, float]]:
        """Extract all available quantity/price pairs."""
        qty_price_pairs = []
        text = soup.get_text()
        
        pricing_patterns = [
            r'(\d+)-(\d+)\s*units:\s*\$(\d+\.\d+)',
            r'(\d+)\+?\s*units:\s*\$(\d+\.\d+)',
            r'(\d+)\s*-\s*(\d+)\s*pcs\s*\$(\d+\.\d+)',
            r'(\d+)\+\s*pcs\s*\$(\d+\.\d+)',
            r'(\d+)\s*\$(\d+\.\d+)',
        ]
        
        for pattern in pricing_patterns:
            matches = re.findall(pattern, text, re.IGNORECASE)
            for match in matches:
                if len(match) == 3:
                    start_qty, end_qty, price = match
                    qty = int(start_qty)
                    price = float(price)
                    if qty > 0:
                        qty_price_pairs.append((qty, price))
                elif len(match) == 2:
                    qty_str, price_str = match
                    qty = int(qty_str) 
                    price = float(price_str)
                    if qty > 0:
                        qty_price_pairs.append((qty, price))
        
        price_elements = soup.find_all(['td', 'span'], string=re.compile(r'\$\d+\.\d+'))
        for price_elem in price_elements:
            price_text = price_elem.get_text(strip=True)
            price_match = re.search(r'\$(\d+\.\d+)', price_text)
            if price_match:
                price = float(price_match.group(1))
                parent = price_elem.parent
                if parent:
                    siblings = parent.find_all(['td', 'span'])
                    for sibling in siblings:
                        qty_text = sibling.get_text(strip=True)
                        qty_match = re.search(r'^(\d+)(?:\+|-)|\b(\d+)\s*(?:pcs?|units?)', qty_text)
                        if qty_match:
                            qty = int(qty_match.group(1) or qty_match.group(2))
                            if qty > 0:
                                qty_price_pairs.append((qty, price))
                            break
        
        # Remove duplicates and keep the lowest price for each quantity
        qty_price_dict: Dict[int, float] = {}
        for qty, price in qty_price_pairs:
            if qty not in qty_price_dict or price < qty_price_dict[qty]:
                qty_price_dict[qty] = price
        
        # Return sorted list of (quantity, price) pairs
        return [(qty, price) for qty, price in sorted(qty_price_dict.items())]


class Board:
    """Class to represent a board with its components and quantities."""
    
    def __init__(self, title: Optional[str] = None, board_quantities: Optional[List[int]] = None):
        self.title = title
        self.components_with_quantities: List[Tuple[Component, int]] = []
        self.board_quantities = board_quantities or [1, 50, 500]
    
    def add_component(self, component: Component, quantity: int) -> None:
        """Add a component with its quantity per board."""
        self.components_with_quantities.append((component, quantity))
    
    def get_components(self) -> List[Tuple[Component, int]]:
        """Get list of (component, quantity) tuples."""
        return self.components_with_quantities
    
    def get_title(self) -> Optional[str]:
        """Get the board title."""
        return self.title
    
    def set_title(self, title: str) -> None:
        """Set the board title."""
        self.title = title
    
    def calculate_totals(self) -> Dict[int, float]:
        """Calculate total cost for different board quantities."""
        totals: Dict[int, float] = {qty: 0.0 for qty in self.board_quantities}
        
        for component, pieces_per_board in self.components_with_quantities:
            for board_count in self.board_quantities:
                total_price = component.get_total_price(board_count, pieces_per_board)
                if total_price is not None:
                    totals[board_count] += total_price
        
        return totals
    
    def calculate_setup_fee(self) -> float:
        """Calculate total setup fee for non-basic components."""
        setup_fee_count = sum(1 for component, _ in self.components_with_quantities 
                             if not component.is_basic_part())
        return setup_fee_count * 3.0
    
    def render_table(self) -> str:
        """Render the board as a formatted table with dynamic columns."""
        if not self.components_with_quantities:
            return "No data to display"
        
        lines = []
        
        # Add title if provided
        if self.title:
            lines.append(f"\n{self.title}")
            lines.append("=" * len(self.title))
        
        # Define column widths
        component_width = 22
        number_width = 9
        pcs_width = 3
        base_width = 4
        eco_width = 3
        price_width = 7
        
        # Build header dynamically
        header_parts = [
            f"{'Component':<{component_width}}",
            f"{'Number':<{number_width}}",
            f"{'Pcs':<{pcs_width}}",
            f"{'Base':<{base_width}}",
            f"{'Eco':<{eco_width}}"
        ]
        
        for qty in self.board_quantities:
            header_parts.append(f"{f'{qty} pcs':<{price_width}}")
        
        header = " | ".join(header_parts)
        lines.append(header)
        lines.append("-" * len(header))
        
        # Print data for each component
        for component, pieces_per_board in self.components_with_quantities:
            name = component.get_component_name()[:component_width]
            number = component.get_part_number()
            base = component.get_base_type()
            eco = component.get_eco_type()
            
            # Build row parts with proper formatting
            row_parts = [
                f"{name:<{component_width}}",
                f"{number:<{number_width}}",
                f"{pieces_per_board:<{pcs_width}}",
                f"{base:<{base_width}}",
                f"{eco:<{eco_width}}"
            ]
            
            # Add pricing columns dynamically
            for qty in self.board_quantities:
                price = component.get_unit_price(qty, pieces_per_board)
                price_str = f"{price:.4f}" if price is not None else "-"
                row_parts.append(f"{price_str:<{price_width}}")
            
            lines.append(" | ".join(row_parts))
        
        # Calculate and display totals
        totals = self.calculate_totals()
        setup_fee = self.calculate_setup_fee()
        
        # Add totals row
        lines.append("-" * len(header))
        row_parts = [
            f"{'TOTAL':<{component_width}}",
            f"{'':>{number_width}}",
            f"{'':>{pcs_width}}",
            f"{'':>{base_width}}",
            f"{'':>{eco_width}}"
        ]
        
        for qty in self.board_quantities:
            total = totals[qty]
            total_str = f"{total:.4f}" if total > 0 else "-"
            row_parts.append(f"{total_str:<{price_width}}")
        lines.append(" | ".join(row_parts))
        
        # Add setup fee per board row
        row_parts = [
            f"{'SETUP FEE PER BOARD':<{component_width}}",
            f"{'':>{number_width}}",
            f"{'':>{pcs_width}}",
            f"{'':>{base_width}}",
            f"{'':>{eco_width}}"
        ]
        
        for qty in self.board_quantities:
            setup_fee_per_board = f"{setup_fee / qty:.4f}" if setup_fee > 0 else "-"
            row_parts.append(f"{setup_fee_per_board:<{price_width}}")
        lines.append(" | ".join(row_parts))
        
        # Add grand total per board
        if any(totals[qty] > 0 for qty in self.board_quantities) or setup_fee > 0:
            lines.append("-" * len(header))
            row_parts = [
                f"{'PRICE PER BOARD':<{component_width}}",
                f"{'':>{number_width}}",
                f"{'':>{pcs_width}}",
                f"{'':>{base_width}}",
                f"{'':>{eco_width}}"
            ]
            
            for qty in self.board_quantities:
                grand_total = totals[qty] + (setup_fee / qty)
                grand_total_str = f"{grand_total:.4f}"
                row_parts.append(f"{grand_total_str:<{price_width}}")
            lines.append(" | ".join(row_parts))
        
        return "\n".join(lines)
    
    def display_table(self) -> str:
        """Render the table to console and return the content."""
        content = self.render_table()
        print(content)
        return content


def read_part_numbers(filename: str) -> List[Tuple[str, List[Tuple[str, int]]]]:
    """Read part numbers and quantities from file, grouped by empty lines with titles."""
    try:
        groups: List[Tuple[str, List[Tuple[str, int]]]] = []
        current_group: List[Tuple[str, int]] = []
        current_title = None
        
        with open(filename, 'r') as f:
            for line_num, line in enumerate(f, 1):
                original_line = line.strip()
                
                # Empty line - start new group if current group has items
                if not original_line:
                    if current_group:
                        groups.append((current_title or f"Group {len(groups) + 1}", current_group))
                        current_group = []
                        current_title = None
                    continue
                
                # Check if line is a comment (starts with #)
                if original_line.startswith('#'):
                    comment = original_line[1:].strip()
                    # If this is the first line of a new group (no parts yet), use as title
                    if not current_group:
                        current_title = comment
                    continue
                    
                # Remove inline comments (everything after #)
                line = original_line
                if '#' in line:
                    line = line.split('#')[0].strip()
                
                # Skip if line is empty after comment removal
                if not line:
                    continue
                
                # Parse part number and quantity
                parts_line = line.split()
                if len(parts_line) == 1:
                    # Default to 1 piece if no quantity specified
                    current_group.append((parts_line[0], 1))
                elif len(parts_line) == 2:
                    try:
                        quantity = int(parts_line[1])
                        current_group.append((parts_line[0], quantity))
                    except ValueError:
                        print(f"Error: Invalid quantity on line {line_num}: {parts_line[1]}")
                        sys.exit(1)
                else:
                    print(f"Error: Invalid format on line {line_num}: {line}")
                    sys.exit(1)
        
        # Add the last group if it has items
        if current_group:
            groups.append((current_title or f"Group {len(groups) + 1}", current_group))
            
        return groups
    except FileNotFoundError:
        print(f"Error: Could not find file {filename}")
        sys.exit(1)


def write_tables_to_markdown(input_filename: str, table_contents: List[str]) -> None:
    """Write table contents to a markdown file with .table.md extension."""
    output_filename = input_filename.rsplit('.', 1)[0] + '.table.md'
    
    try:
        with open(output_filename, 'w') as f:
            f.write("# JLCPCB Component Pricing Tables\n\n")
            for content in table_contents:
                f.write(content + "\n\n")
        print(f"Tables written to {output_filename}")
    except IOError as e:
        print(f"Error writing to {output_filename}: {e}")




def main():
    """Main function."""
    if len(sys.argv) != 2:
        print("Usage: fetch_jlcpcb_prices.py <part_numbers_file>")
        sys.exit(1)
    
    part_numbers_file = sys.argv[1]
    
    print(f"Reading part numbers from {part_numbers_file}...")
    groups = read_part_numbers(part_numbers_file)
    
    if not groups:
        print("No component groups found")
        return
    
    print(f"Found {len(groups)} component groups")
    
    table_contents = []
    
    # Process each group separately
    for group_idx, (title, group) in enumerate(groups, 1):
        print(f"\nProcessing Group {group_idx}: {title} - {len(group)} components...")
        
        # Create board for this group
        board = Board(title)
        total_components = sum(len(g[1]) for g in groups)
        component_counter = sum(len(groups[i][1]) for i in range(group_idx - 1))
        
        for part_number, pieces_per_board in group:
            component_counter += 1
            print(f"Fetching {part_number} ({component_counter}/{total_components})...")
            component = Component(part_number)
            if component.fetch_from_jlcpcb(pieces_per_board):
                board.add_component(component, pieces_per_board)
            
            # Be respectful to the server
            time.sleep(2)
        
        # Display results for this group and collect content
        table_content = board.display_table()
        table_contents.append(table_content)
        print()  # Extra line between groups
    
    # Write all tables to markdown file
    write_tables_to_markdown(part_numbers_file, table_contents)

if __name__ == "__main__":
    main()
