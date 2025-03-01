document.addEventListener("DOMContentLoaded", async function () {
    const imageGrid = document.getElementById("imageGrid");
    const dropdown = document.getElementById("detailDropdown");

    async function fetchJSON(url) {
        const response = await fetch(url);
        return response.json();
    }

    function getQueryParam(name) {
        const params = new URLSearchParams(window.location.search);
        return params.get(name);
    }

    async function loadGrid() {
        const id = getQueryParam("id");

        if (id) {
            // Load neighbors if an ID is provided
            const neighbors = await fetchJSON(`/neighbors?id=${id}`);

            // Create a dropdown for levels of detail
            createDetailDropdown(neighbors);

            // Load the default neighbor images (using the first key as default)
            const defaultLevel = Object.keys(neighbors)[0];
            updateNeighborGrid(neighbors, defaultLevel);

            // Add event listener to the dropdown to update the grid on change
            dropdown.addEventListener("change", function () {
                updateNeighborGrid(neighbors, dropdown.value);
            });
        } else {
            // Load the first page of images
            const ids = await fetchJSON("/firstPage");
            imageGrid.innerHTML = "";
            ids.forEach(id => addImageToGrid(id, imageGrid));
        }
    }

    function addImageToGrid(id, container) {
        const imageContainer = document.createElement("div");
        imageContainer.classList.add("image-container");

        const img = document.createElement("img");
        img.src = `/productImage?id=${id}`;
        img.dataset.id = id;
        img.addEventListener("click", () => zoomIntoID(id));

        const link = document.createElement("a");
        link.href = `/productRedirect?id=${id}`;
        link.classList.add("image-link");
        link.textContent = "🔗"; // You can replace this with an icon or text
        link.target = "_blank"; // Opens in a new tab
        link.rel = "noopener noreferrer"; // Security best practice

        imageContainer.appendChild(img);
        imageContainer.appendChild(link);
        container.appendChild(imageContainer);
    }

    function zoomIntoID(id) {
        window.location = `?id=${id}`;
    }

    function createDetailDropdown(neighbors) {
        dropdown.innerHTML = "";
        Object.keys(neighbors).forEach(level => {
            const option = document.createElement("option");
            option.value = level;
            option.textContent = `Detail Level: ${level}`;
            dropdown.appendChild(option);
        });
        dropdown.style.display = '';
    }

    function updateNeighborGrid(neighbors, level) {
        imageGrid.innerHTML = "";
        neighbors[level].forEach(id => addImageToGrid(id, imageGrid));
    }

    loadGrid();
});