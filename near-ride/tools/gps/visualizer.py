"""
Visualization utilities for GPS trajectory analysis
"""

import matplotlib.pyplot as plt
import pandas as pd
import numpy as np
from typing import Dict, List, Optional, Any
import logging

logger = logging.getLogger(__name__)

try:
    import folium
    FOLIUM_AVAILABLE = True
except ImportError:
    FOLIUM_AVAILABLE = False
    logger.warning("Folium not available. Map visualizations will be disabled.")


class TrajectoryVisualizer:
    """Visualization utilities for GPS trajectories"""
    
    def __init__(self):
        """Initialize visualizer"""
        pass
    
    def plot_similarity_distribution(self, similarity_scores: List[float], 
                                   title: str = "Similarity Score Distribution",
                                   save_path: Optional[str] = None):
        """
        Plot distribution of similarity scores
        
        Args:
            similarity_scores: List of similarity scores
            title: Plot title
            save_path: Optional path to save the plot
        """
        plt.figure(figsize=(10, 6))
        plt.hist(similarity_scores, bins=20, alpha=0.7, color='skyblue', edgecolor='black')
        mean_score = float(np.mean(similarity_scores))
        median_score = float(np.median(similarity_scores))
        plt.axvline(mean_score, color='red', linestyle='--', label=f'Mean: {mean_score:.3f}')
        plt.axvline(median_score, color='orange', linestyle='--', label=f'Median: {median_score:.3f}')
        plt.xlabel('Similarity Score')
        plt.ylabel('Frequency')
        plt.title(title)
        plt.legend()
        plt.grid(True, alpha=0.3)
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            logger.info(f"Similarity distribution plot saved to {save_path}")
        plt.show()
    
    def plot_similarity_matrix(self, similarity_matrix: pd.DataFrame,
                             title: str = "Trajectory Similarity Matrix",
                             save_path: Optional[str] = None):
        """Plot similarity matrix as heatmap."""
        pivot_matrix = similarity_matrix.pivot_table(
            index='user1_id', columns='user2_id', values='similarity_score'
        )
        plt.figure(figsize=(12, 10))
        im = plt.imshow(pivot_matrix.values, cmap='coolwarm', aspect='auto')
        plt.colorbar(im, label='Similarity Score')
        plt.xlabel('User ID')
        plt.ylabel('User ID')
        plt.title(title)
        plt.xticks(range(len(pivot_matrix.columns)), [str(col) for col in pivot_matrix.columns], rotation=45)
        plt.yticks(range(len(pivot_matrix.index)), [str(idx) for idx in pivot_matrix.index])
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            logger.info(f"Similarity matrix plot saved to {save_path}")
        plt.show()
    
    def plot_trajectory_on_map(self, trajectories: Dict[str, pd.DataFrame],
                             center_lat: float = 25.0330, center_lon: float = 121.5654,
                             save_path: Optional[str] = None) -> Optional[str]:
        """Plot trajectories on an interactive map."""
        if not FOLIUM_AVAILABLE:
            logger.warning("Folium not available. Cannot create map visualization.")
            return None
        m = folium.Map(location=[center_lat, center_lon], zoom_start=12)
        colors = ['red', 'blue', 'green', 'purple', 'orange', 'darkred',
                  'darkblue', 'darkgreen', 'cadetblue', 'darkpurple']
        for i, (user_id, trajectory) in enumerate(trajectories.items()):
            if trajectory.empty:
                continue
            color = colors[i % len(colors)]
            coords = trajectory[['latitude', 'longitude']].values.tolist()
            folium.PolyLine(coords, color=color, weight=3, opacity=0.8,
                            popup=f'User: {user_id}').add_to(m)
            folium.Marker(coords[0], popup=f'Start - User: {user_id}',
                          icon=folium.Icon(color='green', icon='play')).add_to(m)
            folium.Marker(coords[-1], popup=f'End - User: {user_id}',
                          icon=folium.Icon(color='red', icon='stop')).add_to(m)
        if save_path:
            m.save(save_path)
            logger.info(f"Map saved to {save_path}")
        return m._repr_html_()
    
    def plot_trajectory_statistics(self, analysis_results: Dict[str, Any],
                                 save_path: Optional[str] = None):
        """Plot trajectory statistics."""
        fig, axes = plt.subplots(2, 2, figsize=(15, 10))
        similarity_scores = analysis_results['similarity_matrix']['similarity_score']
        axes[0, 0].hist(similarity_scores, bins=20, alpha=0.7, color='skyblue')
        axes[0, 0].set_xlabel('Similarity Score')
        axes[0, 0].set_ylabel('Frequency')
        axes[0, 0].set_title('Similarity Score Distribution')
        axes[0, 0].grid(True, alpha=0.3)
        if 'trajectory_stats' in analysis_results:
            axes[0, 1].text(0.5, 0.5, 'Trajectory Length\nDistribution\n(Data needed)',
                           ha='center', va='center', transform=axes[0, 1].transAxes)
        axes[0, 1].set_title('Trajectory Length Distribution')
        temporal_overlaps = analysis_results['similarity_matrix']['temporal_overlap']
        axes[1, 0].hist(temporal_overlaps, bins=20, alpha=0.7, color='lightgreen')
        axes[1, 0].set_xlabel('Temporal Overlap')
        axes[1, 0].set_ylabel('Frequency')
        axes[1, 0].set_title('Temporal Overlap Distribution')
        axes[1, 0].grid(True, alpha=0.3)
        stats_text = f"""
        Number of Users: {analysis_results['num_users']}
        Number of Comparisons: {analysis_results['num_comparisons']}
        Average Similarity: {analysis_results['average_similarity']:.3f}
        Max Similarity: {analysis_results['max_similarity']:.3f}
        Min Similarity: {analysis_results['min_similarity']:.3f}
        """
        axes[1, 1].text(0.1, 0.5, stats_text, transform=axes[1, 1].transAxes,
                        fontsize=12, verticalalignment='center')
        axes[1, 1].set_title('Summary Statistics')
        axes[1, 1].axis('off')
        plt.tight_layout()
        if save_path:
            plt.savefig(save_path, dpi=300, bbox_inches='tight')
            logger.info(f"Statistics plot saved to {save_path}")
        plt.show()
    
    def create_similarity_report_with_plots(self, analysis_results: Dict[str, Any],
                                          output_dir: str = "output") -> str:
        """Create an HTML report with visualizations."""
        import os
        os.makedirs(output_dir, exist_ok=True)
        similarity_dist_path = os.path.join(output_dir, "similarity_distribution.png")
        statistics_path = os.path.join(output_dir, "statistics.png")
        similarity_scores = analysis_results['similarity_matrix']['similarity_score'].tolist()
        self.plot_similarity_distribution(similarity_scores, save_path=similarity_dist_path)
        self.plot_trajectory_statistics(analysis_results, save_path=statistics_path)
        html_content = f"""
        <!DOCTYPE html>
        <html><head><title>GPS Trajectory Similarity Analysis Report</title></head>
        <body>
            <h1>GPS Trajectory Similarity Analysis Report</h1>
            <p>Generated: {pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <h2>Summary Statistics</h2>
            <ul>
                <li>Number of users analyzed: {analysis_results['num_users']}</li>
                <li>Number of pairwise comparisons: {analysis_results['num_comparisons']}</li>
                <li>Average similarity score: {analysis_results['average_similarity']:.3f}</li>
                <li>Maximum similarity score: {analysis_results['max_similarity']:.3f}</li>
                <li>Minimum similarity score: {analysis_results['min_similarity']:.3f}</li>
            </ul>
            <h2>Similarity Score Distribution</h2>
            <img src="similarity_distribution.png" alt="Similarity Distribution">
            <h2>Analysis Statistics</h2>
            <img src="statistics.png" alt="Statistics">
            <h2>Top Similar Trajectory Pairs</h2>
            <table border="1" cellpadding="5" cellspacing="0">
                <tr><th>User 1</th><th>User 2</th><th>Similarity Score</th><th>Temporal Overlap</th></tr>
        """
        top_pairs = analysis_results['similarity_matrix'].nlargest(10, 'similarity_score')
        for _, row in top_pairs.iterrows():
            html_content += f"""
                <tr><td>{row['user1_id']}</td><td>{row['user2_id']}</td>
                <td>{row['similarity_score']:.3f}</td><td>{row['temporal_overlap']:.3f}</td></tr>
            """
        html_content += "</table></body></html>"
        report_path = os.path.join(output_dir, "similarity_report.html")
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write(html_content)
        logger.info(f"Comprehensive report saved to {report_path}")
        return report_path


if __name__ == "__main__":
    visualizer = TrajectoryVisualizer()
    sample_scores = np.random.beta(2, 5, 1000).tolist()
    visualizer.plot_similarity_distribution(sample_scores, title="Sample Similarity Distribution")
